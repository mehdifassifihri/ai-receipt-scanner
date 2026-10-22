from datetime import UTC, date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

Currency = Literal["USD", "EUR", "MAD", "CAD", "GBP"]
Category = Literal[
    "Food & Drinks",
    "Shopping",
    "Transport",
    "Groceries",
    "Health",
    "Entertainment",
    "Utilities",
    "Other",
]
CURRENCIES = ("USD", "EUR", "MAD", "CAD", "GBP")
CATEGORIES = (
    "Food & Drinks",
    "Shopping",
    "Transport",
    "Groceries",
    "Health",
    "Entertainment",
    "Utilities",
    "Other",
)


class Schema(BaseModel):
    model_config = ConfigDict(extra="forbid")


class User(BaseModel):
    id: UUID
    email: str | None = None


class ExpenseFields(Schema):
    merchant: str = Field(min_length=1, max_length=120)
    transaction_date: date
    amount_in_cents: int = Field(gt=0, le=99_999_999_999, strict=True)
    currency: Currency
    category: Category

    @field_validator("merchant")
    @classmethod
    def merchant_not_blank(cls, value):
        if not value.strip():
            raise ValueError("Merchant cannot be blank")
        return value.strip()

    @field_validator("transaction_date")
    @classmethod
    def date_not_future(cls, value):
        if value < date(1900, 1, 1) or value > datetime.now(UTC).date():
            raise ValueError("Transaction date must be between 1900-01-01 and today (UTC)")
        return value


class ExpenseCreate(ExpenseFields):
    receipt_id: UUID | None = None


class Expense(BaseModel):
    id: UUID
    user_id: UUID
    receipt_id: UUID | None
    client_request_id: UUID
    merchant: str
    transaction_date: date
    amount_in_cents: int
    currency: Currency
    category: Category
    created_at: datetime
    updated_at: datetime


class ExpensePage(Schema):
    items: list[Expense]
    total: int
    limit: int
    offset: int


class Receipt(BaseModel):
    id: UUID
    user_id: UUID
    storage_path: str
    sha256: str
    mime_type: Literal["image/jpeg"]
    byte_size: int
    created_at: datetime


class ReceiptImageURL(Schema):
    url: str
    expires_in: int


class RawReceiptExtraction(Schema):
    """Required, nullable fields generate a strict OpenAI JSON schema.

    Dates and money remain strings here, then undergo independent validation.
    A schema-compliant answer is not automatically a verified expense.
    """

    is_receipt: bool
    merchant: str | None
    transaction_date: str | None
    amount: str | None
    currency: str | None
    category: Category | None
    warnings: list[str]


class ExtractedFields(Schema):
    merchant: str | None
    transaction_date: date | None
    amount_in_cents: int | None
    currency: Currency | None
    category: Category | None


class ExtractionDraft(Schema):
    fields: ExtractedFields
    warnings: list[str]
    requires_review: Literal[True] = True


class ExtractionJob(BaseModel):
    id: UUID
    user_id: UUID
    receipt_id: UUID
    model: str
    prompt_version: str
    status: Literal["processing", "completed", "failed"]
    result: ExtractionDraft | None = None
    error_code: str | None = None
    created_at: datetime
    updated_at: datetime


class ExtractionResponse(Schema):
    job: ExtractionJob
    cached: bool


class Health(Schema):
    status: str
    service: str = "snapexpense-api"
