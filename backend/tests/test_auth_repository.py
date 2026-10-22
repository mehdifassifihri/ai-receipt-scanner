import json
from datetime import UTC, date, datetime
from uuid import uuid4

import httpx
import pytest
from conftest import OWNER

from app.auth import AuthenticatedUser
from app.config import Settings
from app.errors import APIError
from app.main import create_app
from app.repository import SupabaseRepository
from app.schemas import User
from app.services.images import PreparedImage


def settings():
    return Settings(
        _env_file=None,
        app_env="test",
        supabase_url="https://unit.supabase.co",
        supabase_publishable_key="publishable-test",
        supabase_service_role_key="service-test",
        openai_api_key=None,
    )


async def test_auth_uses_supabase_verification_and_does_not_trust_unsigned_claims():
    calls = []

    def handle(request):
        calls.append(request)
        assert request.url.path == "/auth/v1/user"
        assert request.headers["apikey"] == "publishable-test"
        if request.headers["authorization"] == "Bearer valid-session":
            return httpx.Response(200, json={"id": str(OWNER), "email": "user@example.test"})
        return httpx.Response(401, json={"message": "invalid JWT"})

    app = create_app(settings())
    async with (
        app.router.lifespan_context(app),
        httpx.AsyncClient(transport=httpx.MockTransport(handle)) as upstream,
    ):
        app.state.http = upstream
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://test"
        ) as client:
            assert (await client.get("/v1/me")).status_code == 401
            assert calls == []
            invalid = await client.get("/v1/me", headers={"Authorization": "Bearer forged-session"})
            assert invalid.status_code == 401
            assert invalid.headers["www-authenticate"] == "Bearer"
            assert "forged-session" not in invalid.text
            valid = await client.get("/v1/me", headers={"Authorization": "Bearer valid-session"})
            assert valid.status_code == 200
            assert valid.json()["id"] == str(OWNER)


async def test_user_requests_keep_rls_token_and_query_owner():
    seen = []

    def handle(request):
        seen.append(request)
        assert request.headers["authorization"] == "Bearer user-session"
        assert request.headers["apikey"] == "publishable-test"
        assert request.url.params["user_id"] == f"eq.{OWNER}"
        return httpx.Response(200, json=[], headers={"content-range": "*/0"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        repository = SupabaseRepository(
            client, settings(), AuthenticatedUser(User(id=OWNER), "user-session")
        )
        assert await repository.list_expenses(search="Coffee", limit=20, offset=0) == ([], 0)
    assert seen[0].url.params["merchant"] == "ilike.%Coffee%"


async def test_job_rpc_alone_uses_server_key_and_passes_verified_owner():
    receipt_id, job_id = uuid4(), uuid4()
    now = datetime.now(UTC).isoformat()

    def handle(request):
        assert request.url.path == "/rest/v1/rpc/claim_extraction"
        assert request.headers["authorization"] == "Bearer service-test"
        body = json.loads(request.content)
        assert body["p_user_id"] == str(OWNER)
        assert body["p_daily_limit"] == 50
        return httpx.Response(
            200,
            json={
                "cached": False,
                "job": {
                    "id": str(job_id),
                    "user_id": str(OWNER),
                    "receipt_id": str(receipt_id),
                    "model": "gpt-5-mini",
                    "prompt_version": "receipt-v1",
                    "status": "processing",
                    "created_at": now,
                    "updated_at": now,
                },
            },
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        repository = SupabaseRepository(
            client, settings(), AuthenticatedUser(User(id=OWNER), "user-session")
        )
        job, cached = await repository.claim_extraction(receipt_id, "gpt-5-mini", "receipt-v1")
        assert job.id == job_id
        assert cached is False


@pytest.mark.parametrize(
    "message,status,code",
    [
        ("EXTRACTION_BUSY", 409, "extraction_in_progress"),
        ("EXTRACTION_DAILY_LIMIT", 429, "extraction_daily_limit"),
        ("RECEIPT_NOT_FOUND", 404, "receipt_not_found"),
    ],
)
async def test_rpc_errors_are_sanitized(message, status, code):
    def handle(_request):
        return httpx.Response(
            400, json={"code": "P0001", "message": message, "details": "sensitive server internals"}
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        repository = SupabaseRepository(
            client, settings(), AuthenticatedUser(User(id=OWNER), "user-session")
        )
        with pytest.raises(APIError) as error:
            await repository.claim_extraction(uuid4(), "model", "v1")
    assert error.value.status == status
    assert error.value.code == code
    assert "sensitive" not in error.value.message


async def test_analytics_reads_past_supabase_page_cap():
    offsets = []
    now = datetime.now(UTC).isoformat()

    def row():
        return {
            "id": str(uuid4()),
            "user_id": str(OWNER),
            "receipt_id": None,
            "client_request_id": str(uuid4()),
            "merchant": "Shop",
            "transaction_date": "2026-10-18",
            "amount_in_cents": 1,
            "currency": "USD",
            "category": "Other",
            "created_at": now,
            "updated_at": now,
        }

    def handle(request):
        offset = int(request.url.params["offset"])
        offsets.append(offset)
        count = 1000 if offset == 0 else 1
        return httpx.Response(
            200,
            json=[row() for _ in range(count)],
            headers={"content-range": f"{offset}-{offset + count - 1}/1001"},
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        repository = SupabaseRepository(
            client, settings(), AuthenticatedUser(User(id=OWNER), "user-session")
        )
        records = await repository.analytics_expenses("USD", date(2026, 10, 1), date(2026, 10, 18))
    assert len(records) == 1001
    assert offsets == [0, 1000]


async def test_upload_database_failure_cleans_only_its_own_object():
    uploaded = []
    deleted = []

    def handle(request):
        if request.url.path == "/rest/v1/receipts" and request.method == "GET":
            return httpx.Response(200, json=[])
        if request.url.path.startswith("/storage/v1/object/receipts/") and request.method == "POST":
            uploaded.append(request.url.path.removeprefix("/storage/v1/object/receipts/"))
            return httpx.Response(200, json={})
        if request.url.path == "/rest/v1/receipts":
            return httpx.Response(503, json={"message": "database unavailable"})
        if request.url.path == "/storage/v1/object/receipts" and request.method == "DELETE":
            deleted.extend(json.loads(request.content)["prefixes"])
            return httpx.Response(200, json=[])
        raise AssertionError(request.url)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        repository = SupabaseRepository(
            client, settings(), AuthenticatedUser(User(id=OWNER), "user-session")
        )
        with pytest.raises(APIError):
            await repository.upload_receipt(PreparedImage(b"image", "a" * 64))
    assert deleted == uploaded
    assert len(deleted) == 1
    assert deleted[0].startswith(f"{OWNER}/")


async def test_lost_insert_response_never_deletes_a_committed_receipt_image():
    committed = []
    deleted = []

    def handle(request):
        if request.url.path == "/rest/v1/receipts" and request.method == "GET":
            return httpx.Response(200, json=committed)
        if request.url.path.startswith("/storage/v1/object/receipts/") and request.method == "POST":
            return httpx.Response(200, json={})
        if request.url.path == "/rest/v1/receipts" and request.method == "POST":
            row = json.loads(request.content)
            row["created_at"] = datetime.now(UTC).isoformat()
            committed.append(row)
            raise httpx.ReadTimeout("response lost after commit", request=request)
        if request.method == "DELETE":
            deleted.append(request)
            return httpx.Response(200, json=[])
        raise AssertionError(request.url)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        repository = SupabaseRepository(
            client, settings(), AuthenticatedUser(User(id=OWNER), "user-session")
        )
        receipt, reused = await repository.upload_receipt(PreparedImage(b"image", "a" * 64))
    assert reused is True
    assert receipt.storage_path == committed[0]["storage_path"]
    assert deleted == []


@pytest.mark.parametrize(
    "bucket,status",
    [
        ({"public": False, "file_size_limit": 6291456}, 200),
        ({"public": True, "file_size_limit": 6291456}, 503),
        ({"public": False, "file_size_limit": None}, 503),
        ([], 503),
    ],
)
async def test_readiness_checks_private_storage_without_calling_openai(bucket, status):
    config = settings().model_copy(update={"openai_api_key": None})
    # Readiness needs the key to be configured, but never actually invokes it.
    from pydantic import SecretStr

    config.openai_api_key = SecretStr("sk-test-only")
    urls = []

    def handle(request):
        urls.append(str(request.url))
        if request.url.path.startswith("/storage/v1/bucket/"):
            return httpx.Response(200, json=bucket)
        assert request.url.path.startswith("/rest/v1/")
        return httpx.Response(200, json=[])

    app = create_app(config)
    async with (
        app.router.lifespan_context(app),
        httpx.AsyncClient(transport=httpx.MockTransport(handle)) as upstream,
    ):
        app.state.http = upstream
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.get("/ready")
    assert response.status_code == status
    assert len(urls) == 4
    if status == 200:
        assert response.json()["openai"] == "configured_not_live_tested"
