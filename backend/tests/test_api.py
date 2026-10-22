import io
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from conftest import OTHER
from PIL import Image

from app.errors import APIError


def image_bytes():
    output = io.BytesIO()
    Image.new("RGB", (100, 200), "white").save(output, "PNG")
    return output.getvalue()


def upload(client):
    response = client.post(
        "/v1/receipts", files={"file": ("receipt.png", image_bytes(), "image/png")}
    )
    assert response.status_code in {200, 201}, response.text
    return response.json()


def payload(**updates):
    return {
        "merchant": "Starbucks",
        "transaction_date": datetime.now(UTC).date().isoformat(),
        "amount_in_cents": 2450,
        "currency": "MAD",
        "category": "Food & Drinks",
        **updates,
    }


def test_health_and_documentation_without_credentials(harness):
    client, _, _ = harness
    assert client.get("/health").json()["status"] == "ok"
    response = client.get("/ready")
    assert response.status_code == 503
    assert "OPENAI_API_KEY" in response.json()["missing"]
    assert client.get("/docs").status_code == 200
    schema = client.get("/openapi.json").json()
    assert "/v1/receipts/{receipt_id}/extract" in schema["paths"]
    assert "HTTPBearer" in schema["components"]["securitySchemes"]
    assert client.get("/health").headers["x-request-id"]


def test_upload_extract_confirm_edit_delete_flow(harness):
    client, repository, extractor = harness
    receipt = upload(client)
    assert receipt["mime_type"] == "image/jpeg"
    assert len(repository.receipts) == 1
    assert upload(client)["id"] == receipt["id"]
    response = client.post(f"/v1/receipts/{receipt['id']}/extract")
    assert response.status_code == 200, response.text
    assert response.json()["job"]["result"]["requires_review"] is True
    assert repository.expenses == {}  # Extraction never silently saves an expense.
    repeated = client.post(f"/v1/receipts/{receipt['id']}/extract")
    assert repeated.json()["cached"] is True
    assert extractor.calls == 1
    key = str(uuid4())
    fields = payload(receipt_id=receipt["id"])
    saved = client.post("/v1/expenses", json=fields, headers={"Idempotency-Key": key})
    assert saved.status_code == 201, saved.text
    expense = saved.json()
    retry = client.post("/v1/expenses", json=fields, headers={"Idempotency-Key": key})
    assert retry.status_code == 200
    assert retry.json()["id"] == expense["id"]
    conflict = client.post(
        "/v1/expenses",
        json=payload(receipt_id=receipt["id"], merchant="Different"),
        headers={"Idempotency-Key": key},
    )
    assert conflict.status_code == 409
    assert client.get("/v1/expenses?search=star&category=Food%20%26%20Drinks").json()["total"] == 1
    updated = client.put(f"/v1/expenses/{expense['id']}", json=payload(amount_in_cents=3000))
    assert updated.status_code == 200
    assert updated.json()["receipt_id"] == receipt["id"]
    report = client.get("/v1/analytics?currency=MAD").json()
    assert report["total_in_cents"] == 3000
    assert report["categories"][0]["percentage"] == 100
    preview = client.get(f"/v1/receipts/{receipt['id']}/image-url")
    assert preview.status_code == 200
    assert preview.json()["expires_in"] == 300
    assert preview.headers["cache-control"] == "no-store"
    assert client.delete(f"/v1/expenses/{expense['id']}").status_code == 204
    assert client.get("/v1/expenses").json()["total"] == 0
    assert len(repository.receipts) == 1
    assert len(repository.images) == 1


@pytest.mark.parametrize(
    "updates",
    [
        {"merchant": "  "},
        {"amount_in_cents": 0},
        {"amount_in_cents": -1},
        {"amount_in_cents": 24.5},
        {"amount_in_cents": "2450"},
        {"currency": "XYZ"},
        {"category": "Unrecognized"},
        {"transaction_date": (datetime.now(UTC).date() + timedelta(days=1)).isoformat()},
        {"user_id": str(OTHER)},
    ],
)
def test_invalid_expense_never_saved(harness, updates):
    client, repository, _ = harness
    response = client.post(
        "/v1/expenses", json=payload(**updates), headers={"Idempotency-Key": str(uuid4())}
    )
    assert response.status_code == 422
    assert repository.expenses == {}
    assert all("input" not in field for field in response.json().get("fields", []))


def test_idempotency_key_is_required(harness):
    client, _, _ = harness
    assert client.post("/v1/expenses", json=payload()).status_code == 422


def test_other_user_cannot_read_edit_delete_or_extract(harness):
    client, repository, extractor = harness
    receipt = upload(client)
    saved = client.post(
        "/v1/expenses",
        json=payload(receipt_id=receipt["id"]),
        headers={"Idempotency-Key": str(uuid4())},
    ).json()
    repository.user_id = OTHER
    assert client.get(f"/v1/receipts/{receipt['id']}").status_code == 404
    assert client.get(f"/v1/receipts/{receipt['id']}/image-url").status_code == 404
    assert client.post(f"/v1/receipts/{receipt['id']}/extract").status_code == 404
    assert client.get(f"/v1/expenses/{saved['id']}").status_code == 404
    assert client.put(f"/v1/expenses/{saved['id']}", json=payload()).status_code == 404
    assert client.delete(f"/v1/expenses/{saved['id']}").status_code == 404
    assert client.get("/v1/expenses").json()["total"] == 0
    assert extractor.calls == 0


def test_extraction_failure_is_recorded_and_retry_can_succeed(harness):
    client, repository, extractor = harness
    receipt = upload(client)
    extractor.error = APIError(504, "extraction_timeout", "Timed out")
    assert client.post(f"/v1/receipts/{receipt['id']}/extract").status_code == 504
    status = client.get(f"/v1/receipts/{receipt['id']}/extraction").json()
    assert status["status"] == "failed"
    assert status["error_code"] == "extraction_timeout"
    extractor.error = None
    assert client.post(f"/v1/receipts/{receipt['id']}/extract").status_code == 200
    assert repository.expenses == {}


def test_quota_and_tampered_image_do_not_call_openai(harness):
    client, repository, extractor = harness
    receipt = upload(client)
    repository.quota = 0
    assert client.post(f"/v1/receipts/{receipt['id']}/extract").status_code == 429
    assert extractor.calls == 0
    repository.quota = 50
    original_id = next(iter(repository.images))
    repository.images[original_id] = b"changed"
    assert client.post(f"/v1/receipts/{receipt['id']}/extract").status_code == 422
    assert extractor.calls == 0


def test_upload_type_limits_and_date_range(harness):
    client, repository, _ = harness
    assert (
        client.post(
            "/v1/receipts", files={"file": ("bad.jpg", b"not-an-image", "image/jpeg")}
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/v1/receipts", files={"file": ("bad.svg", b"<svg/>", "image/svg+xml")}
        ).status_code
        == 415
    )
    assert (
        client.post(
            "/v1/receipts", files={"file": ("wrong.jpg", image_bytes(), "image/jpeg")}
        ).status_code
        == 415
    )
    assert client.get("/v1/expenses?date_from=2026-10-19&date_to=2026-10-01").status_code == 422
    response = client.post("/v1/receipts", content=b"x" * (6 * 1024 * 1024 + 65537))
    assert response.status_code == 413
    assert response.headers["x-request-id"]
    assert repository.receipts == {}
