from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

from app.auth import AuthenticatedUser, get_current_user
from app.config import Settings
from app.errors import APIError
from app.main import create_app
from app.repository import get_repository
from app.schemas import Expense, ExtractedFields, ExtractionDraft, ExtractionJob, Receipt, User

OWNER = UUID("11111111-1111-4111-8111-111111111111")
OTHER = UUID("22222222-2222-4222-8222-222222222222")


class MemoryRepository:
    """Test double only; the running application always uses Supabase."""

    def __init__(self):
        self.receipts = {}
        self.images = {}
        self.expenses = {}
        self.jobs = {}
        self.quota = 50
        self.user_id = OWNER
        self.created_jobs = 0

    async def get_receipt(self, receipt_id):
        receipt = self.receipts.get(receipt_id)
        if receipt is None or receipt.user_id != self.user_id:
            raise APIError(404, "receipt_not_found", "Receipt not found.")
        return receipt

    async def upload_receipt(self, image):
        for receipt in self.receipts.values():
            if receipt.user_id == self.user_id and receipt.sha256 == image.sha256:
                return receipt, True
        key = uuid4()
        receipt = Receipt(
            id=key,
            user_id=self.user_id,
            storage_path=f"{self.user_id}/{key}.jpg",
            sha256=image.sha256,
            mime_type="image/jpeg",
            byte_size=len(image.data),
            created_at=datetime.now(UTC),
        )
        self.receipts[key] = receipt
        self.images[key] = image.data
        return receipt, False

    async def download_receipt(self, receipt):
        return self.images[receipt.id]

    async def receipt_image_url(self, receipt_id):
        await self.get_receipt(receipt_id)
        return (
            f"https://example.supabase.co/storage/v1/object/sign/receipts/{receipt_id}?token=test"
        )

    async def claim_extraction(self, receipt_id, model, prompt_version):
        await self.get_receipt(receipt_id)
        for job in self.jobs.values():
            if (
                job.user_id == self.user_id
                and job.receipt_id == receipt_id
                and job.status == "completed"
                and job.model == model
                and job.prompt_version == prompt_version
            ):
                return job, True
        if self.created_jobs >= self.quota:
            raise APIError(429, "extraction_daily_limit", "Daily limit reached.")
        now = datetime.now(UTC)
        job = ExtractionJob(
            id=uuid4(),
            user_id=self.user_id,
            receipt_id=receipt_id,
            model=model,
            prompt_version=prompt_version,
            status="processing",
            created_at=now,
            updated_at=now,
        )
        self.jobs[job.id] = job
        self.created_jobs += 1
        return job, False

    async def finish_extraction(self, job_id, *, result=None, error_code=None):
        original = self.jobs[job_id]
        job = original.model_copy(
            update={
                "status": "completed" if result is not None else "failed",
                "result": result,
                "error_code": error_code,
                "updated_at": datetime.now(UTC),
            }
        )
        self.jobs[job_id] = job
        return job

    async def latest_job(self, receipt_id):
        await self.get_receipt(receipt_id)
        matches = [
            job
            for job in self.jobs.values()
            if job.receipt_id == receipt_id and job.user_id == self.user_id
        ]
        if not matches:
            raise APIError(404, "extraction_not_found", "No extraction yet.")
        return matches[-1]

    async def create_expense(self, fields, request_id):
        for item in self.expenses.values():
            if item.user_id == self.user_id and item.client_request_id == request_id:
                if any(getattr(item, key) != value for key, value in fields.model_dump().items()):
                    raise APIError(409, "idempotency_key_reused", "Different payload.")
                return item, True
        if fields.receipt_id:
            await self.get_receipt(fields.receipt_id)
            if any(item.receipt_id == fields.receipt_id for item in self.expenses.values()):
                raise APIError(409, "resource_conflict", "Receipt already saved.")
        now = datetime.now(UTC)
        item = Expense(
            id=uuid4(),
            user_id=self.user_id,
            client_request_id=request_id,
            created_at=now,
            updated_at=now,
            **fields.model_dump(),
        )
        self.expenses[item.id] = item
        return item, False

    async def get_expense(self, expense_id):
        item = self.expenses.get(expense_id)
        if item is None or item.user_id != self.user_id:
            raise APIError(404, "expense_not_found", "Expense not found.")
        return item

    async def update_expense(self, expense_id, fields):
        item = await self.get_expense(expense_id)
        self.expenses[item.id] = item.model_copy(
            update={**fields.model_dump(), "updated_at": datetime.now(UTC)}
        )
        return self.expenses[item.id]

    async def delete_expense(self, expense_id):
        await self.get_expense(expense_id)
        del self.expenses[expense_id]

    async def list_expenses(self, **filters):
        values = [item for item in self.expenses.values() if item.user_id == self.user_id]
        values = [
            item
            for item in values
            if (not filters.get("search") or filters["search"].lower() in item.merchant.lower())
            and (not filters.get("category") or item.category == filters["category"])
            and (not filters.get("currency") or item.currency == filters["currency"])
            and (not filters.get("start") or item.transaction_date >= filters["start"])
            and (not filters.get("end") or item.transaction_date <= filters["end"])
        ]
        values.sort(key=lambda item: item.transaction_date, reverse=True)
        offset, limit = filters.get("offset", 0), filters.get("limit", 20)
        return values[offset : offset + limit], len(values)

    async def analytics_expenses(self, currency, start, end):
        return (await self.list_expenses(currency=currency, start=start, end=end, limit=10000))[0]


class FakeExtractor:
    def __init__(self):
        self.calls = 0
        self.error = None

    async def extract(self, _image):
        self.calls += 1
        if self.error:
            raise self.error
        return ExtractionDraft(
            fields=ExtractedFields(
                merchant="Starbucks",
                transaction_date=datetime.now(UTC).date(),
                amount_in_cents=2450,
                currency="MAD",
                category="Food & Drinks",
            ),
            warnings=[],
        )


@pytest.fixture
def harness():
    settings = Settings(
        _env_file=None,
        app_env="test",
        supabase_url=None,
        supabase_publishable_key=None,
        supabase_service_role_key=None,
        openai_api_key=None,
        max_upload_bytes=6 * 1024 * 1024,
    )
    app = create_app(settings)
    repository = MemoryRepository()
    extractor = FakeExtractor()
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(
        User(id=repository.user_id), "test-access-token"
    )
    app.dependency_overrides[get_repository] = lambda: repository
    with TestClient(app) as client:
        app.state.extractor = extractor
        yield client, repository, extractor
