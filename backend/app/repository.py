import logging
from datetime import date
from urllib.parse import quote, urljoin, urlsplit
from uuid import UUID, uuid4

import httpx
from fastapi import Depends, Request
from pydantic import ValidationError

from .auth import AuthenticatedUser, get_current_user
from .config import Settings
from .errors import APIError
from .schemas import Expense, ExpenseCreate, ExpenseFields, ExtractionDraft, ExtractionJob, Receipt
from .services.images import PreparedImage

logger = logging.getLogger(__name__)


class SupabaseRepository:
    """Per-request credentials: user JWT for RLS, server key only for job administration."""

    def __init__(self, http: httpx.AsyncClient, settings: Settings, identity: AuthenticatedUser):
        self.http = http
        self.settings = settings
        self.identity = identity
        self.user_id = str(identity.user.id)

    def headers(self, *, admin: bool = False) -> dict[str, str]:
        key = (
            self.settings.supabase_service_role_key
            if admin
            else self.settings.supabase_publishable_key
        )
        if not self.settings.supabase_url or not key:
            raise APIError(
                503, "supabase_not_configured", "Supabase is not fully configured on this server."
            )
        token = key.get_secret_value() if admin else self.identity.token
        return {"apikey": key.get_secret_value(), "Authorization": f"Bearer {token}"}

    async def request(self, method: str, path: str, *, admin: bool = False, headers=None, **kwargs):
        credentials = self.headers(admin=admin)
        credentials.update(headers or {})
        try:
            response = await self.http.request(
                method, f"{self.settings.supabase_url}{path}", headers=credentials, **kwargs
            )
        except httpx.RequestError as error:
            raise APIError(
                503,
                "storage_or_database_unavailable",
                "Storage or database is temporarily unavailable.",
            ) from error
        if response.is_success:
            return response
        try:
            failure = response.json()
        except ValueError:
            failure = {}
        code = failure.get("code", "") if isinstance(failure, dict) else ""
        message = failure.get("message", "") if isinstance(failure, dict) else ""
        if "EXTRACTION_DAILY_LIMIT" in message:
            raise APIError(
                429,
                "extraction_daily_limit",
                "Your daily extraction limit has been reached. Try again tomorrow (UTC).",
            )
        if "EXTRACTION_BUSY" in message:
            raise APIError(
                409,
                "extraction_in_progress",
                "You already have an extraction in progress. Check its status before retrying.",
            )
        if "RECEIPT_NOT_FOUND" in message:
            raise APIError(404, "receipt_not_found", "Receipt not found.")
        if code in {"23505", "23503"} or response.status_code == 409:
            raise APIError(
                409,
                "resource_conflict",
                "This record already exists or is still referenced by another record.",
            )
        if response.status_code in {401, 403}:
            if admin:
                raise APIError(
                    503,
                    "supabase_admin_unavailable",
                    "Server job administration is not configured correctly.",
                )
            raise APIError(
                401, "invalid_access_token", "Your session is invalid or expired. Sign in again."
            )
        if code in {"PGRST205", "PGRST202", "42P01", "42883"}:
            raise APIError(
                503,
                "database_not_initialized",
                "Apply the backend Supabase migration before using this API.",
            )
        raise APIError(
            502, "supabase_error", "Storage or database could not complete this request."
        )

    @staticmethod
    def rows(response: httpx.Response) -> list[dict]:
        try:
            rows = response.json()
            if not isinstance(rows, list):
                raise ValueError("Expected rows")
            return rows
        except ValueError as error:
            raise APIError(
                502, "invalid_database_response", "The database returned an invalid response."
            ) from error

    async def get_receipt(self, receipt_id: UUID) -> Receipt:
        response = await self.request(
            "GET",
            "/rest/v1/receipts",
            params={
                "id": f"eq.{receipt_id}",
                "user_id": f"eq.{self.user_id}",
                "select": "*",
                "limit": "1",
            },
        )
        rows = self.rows(response)
        if not rows:
            raise APIError(404, "receipt_not_found", "Receipt not found.")
        return Receipt.model_validate(rows[0])

    async def receipt_by_hash(self, sha256: str) -> Receipt | None:
        response = await self.request(
            "GET",
            "/rest/v1/receipts",
            params={
                "sha256": f"eq.{sha256}",
                "user_id": f"eq.{self.user_id}",
                "select": "*",
                "limit": "1",
            },
        )
        rows = self.rows(response)
        return Receipt.model_validate(rows[0]) if rows else None

    async def _remove_object(self, path: str) -> None:
        await self.request(
            "DELETE",
            f"/storage/v1/object/{self.settings.supabase_storage_bucket}",
            json={"prefixes": [path]},
        )

    async def upload_receipt(self, image: PreparedImage) -> tuple[Receipt, bool]:
        existing = await self.receipt_by_hash(image.sha256)
        if existing:
            return existing, True
        receipt_id = uuid4()
        path = f"{self.user_id}/{receipt_id}.jpg"
        await self.request(
            "POST",
            f"/storage/v1/object/{self.settings.supabase_storage_bucket}/{path}",
            content=image.data,
            headers={"Content-Type": image.mime_type, "x-upsert": "false"},
        )
        try:
            response = await self.request(
                "POST",
                "/rest/v1/receipts",
                headers={"Prefer": "return=representation"},
                json={
                    "id": str(receipt_id),
                    "user_id": self.user_id,
                    "storage_path": path,
                    "sha256": image.sha256,
                    "mime_type": image.mime_type,
                    "byte_size": len(image.data),
                },
            )
            return Receipt.model_validate(self.rows(response)[0]), False
        except (APIError, ValidationError, IndexError):
            # A timed-out insert may already have committed. Verify before cleanup
            # so a lost HTTP response cannot cause deletion of a referenced image.
            try:
                winner = await self.receipt_by_hash(image.sha256)
            except APIError:
                logger.warning("receipt_cleanup_deferred", extra={"receipt_id": str(receipt_id)})
                raise
            if winner and winner.storage_path == path:
                return winner, True
            try:
                await self._remove_object(path)
            except APIError:
                logger.warning(
                    "receipt_upload_compensation_failed", extra={"receipt_id": str(receipt_id)}
                )
            if winner:
                return winner, True
            raise

    async def download_receipt(self, receipt: Receipt) -> bytes:
        path = quote(receipt.storage_path, safe="/")
        url = f"{self.settings.supabase_url}/storage/v1/object/authenticated/{self.settings.supabase_storage_bucket}/{path}"
        content = bytearray()
        try:
            async with self.http.stream("GET", url, headers=self.headers()) as response:
                if response.status_code in {401, 403}:
                    raise APIError(
                        401, "invalid_access_token", "Your session is invalid or expired."
                    )
                if not response.is_success:
                    raise APIError(
                        422, "receipt_image_unavailable", "The stored receipt image is unavailable."
                    )
                async for chunk in response.aiter_bytes(65536):
                    content.extend(chunk)
                    if len(content) > self.settings.max_upload_bytes:
                        raise APIError(
                            422,
                            "receipt_image_unavailable",
                            "The stored receipt image is too large.",
                        )
        except httpx.RequestError as error:
            raise APIError(
                503, "storage_unavailable", "Receipt storage is temporarily unavailable."
            ) from error
        if not content:
            raise APIError(422, "receipt_image_unavailable", "The stored receipt image is empty.")
        return bytes(content)

    async def receipt_image_url(self, receipt_id: UUID) -> str:
        receipt = await self.get_receipt(receipt_id)
        path = quote(receipt.storage_path, safe="/")
        response = await self.request(
            "POST",
            f"/storage/v1/object/sign/{self.settings.supabase_storage_bucket}/{path}",
            json={"expiresIn": 300},
        )
        try:
            signed = response.json()["signedURL"]
            url = urljoin(f"{self.settings.supabase_url}/storage/v1/", signed.lstrip("/"))
            if urlsplit(url).netloc != urlsplit(self.settings.supabase_url).netloc:
                raise ValueError("Unexpected storage host")
            return url
        except (ValueError, KeyError, TypeError) as error:
            raise APIError(
                502, "invalid_storage_response", "The receipt preview could not be generated."
            ) from error

    async def latest_job(self, receipt_id: UUID) -> ExtractionJob:
        await self.get_receipt(receipt_id)
        response = await self.request(
            "GET",
            "/rest/v1/extraction_jobs",
            params={
                "receipt_id": f"eq.{receipt_id}",
                "user_id": f"eq.{self.user_id}",
                "order": "created_at.desc,id.desc",
                "limit": "1",
            },
        )
        rows = self.rows(response)
        if not rows:
            raise APIError(404, "extraction_not_found", "This receipt has no extraction job yet.")
        return ExtractionJob.model_validate(rows[0])

    async def claim_extraction(
        self, receipt_id: UUID, model: str, prompt_version: str
    ) -> tuple[ExtractionJob, bool]:
        response = await self.request(
            "POST",
            "/rest/v1/rpc/claim_extraction",
            admin=True,
            json={
                "p_user_id": self.user_id,
                "p_receipt_id": str(receipt_id),
                "p_model": model,
                "p_prompt_version": prompt_version,
                "p_daily_limit": self.settings.extraction_daily_limit,
            },
        )
        try:
            result = response.json()
            return ExtractionJob.model_validate(result["job"]), bool(result["cached"])
        except (ValueError, KeyError, TypeError) as error:
            raise APIError(
                502, "invalid_database_response", "The extraction job could not be created."
            ) from error

    async def finish_extraction(
        self, job_id: UUID, *, result: ExtractionDraft | None = None, error_code: str | None = None
    ) -> ExtractionJob:
        response = await self.request(
            "PATCH",
            "/rest/v1/extraction_jobs",
            admin=True,
            params={
                "id": f"eq.{job_id}",
                "user_id": f"eq.{self.user_id}",
                "status": "eq.processing",
            },
            headers={"Prefer": "return=representation"},
            json={
                "status": "completed" if result is not None else "failed",
                "result": result.model_dump(mode="json") if result is not None else None,
                "error_code": error_code,
            },
        )
        rows = self.rows(response)
        if not rows:
            raise APIError(
                409,
                "extraction_job_changed",
                "The extraction job is no longer active. Retry its status request.",
            )
        return ExtractionJob.model_validate(rows[0])

    async def get_expense(self, expense_id: UUID) -> Expense:
        response = await self.request(
            "GET",
            "/rest/v1/expenses",
            params={
                "id": f"eq.{expense_id}",
                "user_id": f"eq.{self.user_id}",
                "select": "*",
                "limit": "1",
            },
        )
        rows = self.rows(response)
        if not rows:
            raise APIError(404, "expense_not_found", "Expense not found.")
        return Expense.model_validate(rows[0])

    async def _expense_by_request(self, request_id: UUID) -> Expense | None:
        response = await self.request(
            "GET",
            "/rest/v1/expenses",
            params={
                "client_request_id": f"eq.{request_id}",
                "user_id": f"eq.{self.user_id}",
                "limit": "1",
            },
        )
        rows = self.rows(response)
        return Expense.model_validate(rows[0]) if rows else None

    @staticmethod
    def _same_create(expense: Expense, fields: ExpenseCreate) -> bool:
        return {
            key: getattr(expense, key) for key in type(fields).model_fields
        } == fields.model_dump()

    async def create_expense(self, fields: ExpenseCreate, request_id: UUID) -> tuple[Expense, bool]:
        existing = await self._expense_by_request(request_id)
        if existing:
            if not self._same_create(existing, fields):
                raise APIError(
                    409,
                    "idempotency_key_reused",
                    "Use a new Idempotency-Key for a different expense payload.",
                )
            return existing, True
        if fields.receipt_id:
            await self.get_receipt(fields.receipt_id)
        try:
            response = await self.request(
                "POST",
                "/rest/v1/expenses",
                headers={"Prefer": "return=representation"},
                json={
                    **fields.model_dump(mode="json"),
                    "user_id": self.user_id,
                    "client_request_id": str(request_id),
                },
            )
            return Expense.model_validate(self.rows(response)[0]), False
        except APIError as error:
            if error.status == 409:
                winner = await self._expense_by_request(request_id)
                if winner and self._same_create(winner, fields):
                    return winner, True
            raise

    async def update_expense(self, expense_id: UUID, fields: ExpenseFields) -> Expense:
        response = await self.request(
            "PATCH",
            "/rest/v1/expenses",
            params={"id": f"eq.{expense_id}", "user_id": f"eq.{self.user_id}"},
            headers={"Prefer": "return=representation"},
            json=fields.model_dump(mode="json"),
        )
        rows = self.rows(response)
        if not rows:
            raise APIError(404, "expense_not_found", "Expense not found.")
        return Expense.model_validate(rows[0])

    async def delete_expense(self, expense_id: UUID) -> None:
        response = await self.request(
            "DELETE",
            "/rest/v1/expenses",
            params={"id": f"eq.{expense_id}", "user_id": f"eq.{self.user_id}"},
            headers={"Prefer": "return=representation"},
        )
        if not self.rows(response):
            raise APIError(404, "expense_not_found", "Expense not found.")
        # Receipt storage is deliberately retained. Never delete unrelated images.

    async def list_expenses(
        self,
        *,
        limit=20,
        offset=0,
        search=None,
        category=None,
        currency=None,
        start: date | None = None,
        end: date | None = None,
    ) -> tuple[list[Expense], int]:
        params = [
            ("user_id", f"eq.{self.user_id}"),
            ("select", "*"),
            ("order", "transaction_date.desc,created_at.desc,id.desc"),
            ("limit", str(limit)),
            ("offset", str(offset)),
        ]
        if search:
            # PostgREST/SQL pattern characters are supported intentionally; never raw SQL.
            params.append(("merchant", f"ilike.%{search.strip()}%"))
        if category:
            params.append(("category", f"eq.{category}"))
        if currency:
            params.append(("currency", f"eq.{currency}"))
        if start:
            params.append(("transaction_date", f"gte.{start.isoformat()}"))
        if end:
            params.append(("transaction_date", f"lte.{end.isoformat()}"))
        response = await self.request(
            "GET", "/rest/v1/expenses", params=params, headers={"Prefer": "count=exact"}
        )
        try:
            total = int(response.headers["content-range"].split("/")[-1])
        except (KeyError, ValueError) as error:
            raise APIError(
                502, "invalid_database_response", "The expense count could not be read."
            ) from error
        return [Expense.model_validate(row) for row in self.rows(response)], total

    async def analytics_expenses(self, currency: str, start: date, end: date) -> list[Expense]:
        records = []
        offset = 0
        while True:
            page, total = await self.list_expenses(
                limit=1000, offset=offset, currency=currency, start=start, end=end
            )
            records.extend(page)
            offset += len(page)
            if offset >= total:
                return records
            if not page:
                raise APIError(
                    502,
                    "incomplete_database_page",
                    "The complete report could not be loaded. Please retry.",
                )


def get_repository(
    request: Request, identity: AuthenticatedUser = Depends(get_current_user)
) -> SupabaseRepository:
    return SupabaseRepository(request.app.state.http, request.app.state.settings, identity)
