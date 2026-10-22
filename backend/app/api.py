import hashlib
import logging
from datetime import UTC, date, datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, Header, Query, Request, Response, UploadFile
from starlette.concurrency import run_in_threadpool

from .auth import AuthenticatedUser, get_current_user
from .errors import APIError
from .repository import SupabaseRepository, get_repository
from .schemas import (
    CATEGORIES,
    CURRENCIES,
    Category,
    Currency,
    Expense,
    ExpenseCreate,
    ExpenseFields,
    ExpensePage,
    ExtractionJob,
    ExtractionResponse,
    Receipt,
    ReceiptImageURL,
    User,
)
from .services.analytics import Period, SpendingReport, aggregate_expenses, period_range
from .services.ask_snap import AskRequest, AskResponse, answer_question, load_owned_expenses
from .services.extraction import PROMPT_VERSION, OpenAIExtractor
from .services.images import prepare_image

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/v1")
Repository = Annotated[SupabaseRepository, Depends(get_repository)]


def get_extractor(request: Request) -> OpenAIExtractor:
    extractor = request.app.state.extractor
    if extractor is None:
        raise APIError(
            503,
            "openai_not_configured",
            "OpenAI extraction has not been configured on this server.",
        )
    return extractor


@router.get("/me", response_model=User, tags=["Account"])
async def me(identity: Annotated[AuthenticatedUser, Depends(get_current_user)]):
    return identity.user


@router.get("/metadata", tags=["Metadata"])
async def metadata(_identity: Annotated[AuthenticatedUser, Depends(get_current_user)]):
    return {
        "currencies": CURRENCIES,
        "categories": CATEGORIES,
        "amount_unit": "integer_minor_units",
        "date_timezone": "UTC",
    }


@router.post("/receipts", response_model=Receipt, status_code=201, tags=["Receipts"])
async def upload_receipt(
    request: Request,
    response: Response,
    repository: Repository,
    file: Annotated[
        UploadFile, File(description="One JPEG/PNG receipt, maximum 6 MiB and 20 megapixels")
    ],
):
    maximum = request.app.state.settings.max_upload_bytes
    try:
        data = await file.read(maximum + 1)
        async with request.app.state.image_processing_slots:
            image = await run_in_threadpool(prepare_image, data, file.content_type, maximum)
    finally:
        await file.close()
    receipt, reused = await repository.upload_receipt(image)
    if reused:
        response.status_code = 200
    return receipt


@router.get("/receipts/{receipt_id}", response_model=Receipt, tags=["Receipts"])
async def get_receipt(receipt_id: UUID, repository: Repository):
    return await repository.get_receipt(receipt_id)


@router.get("/receipts/{receipt_id}/image-url", response_model=ReceiptImageURL, tags=["Receipts"])
async def image_url(receipt_id: UUID, repository: Repository, response: Response):
    response.headers["Cache-Control"] = "no-store"
    return ReceiptImageURL(url=await repository.receipt_image_url(receipt_id), expires_in=300)


@router.post(
    "/receipts/{receipt_id}/extract", response_model=ExtractionResponse, tags=["Extraction"]
)
async def extract_receipt(
    receipt_id: UUID,
    request: Request,
    repository: Repository,
    extractor: Annotated[OpenAIExtractor, Depends(get_extractor)],
):
    settings = request.app.state.settings
    receipt = await repository.get_receipt(receipt_id)
    job, cached = await repository.claim_extraction(
        receipt_id, settings.openai_model, PROMPT_VERSION
    )
    if cached:
        return ExtractionResponse(job=job, cached=True)
    try:
        image = await repository.download_receipt(receipt)
        if hashlib.sha256(image).hexdigest() != receipt.sha256:
            raise APIError(
                422,
                "receipt_image_changed",
                "The stored image no longer matches this receipt. Upload it again.",
            )
        draft = await extractor.extract(image)
        job = await repository.finish_extraction(job.id, result=draft)
    except Exception as error:
        code = error.code if isinstance(error, APIError) else "extraction_failed"
        try:
            await repository.finish_extraction(job.id, error_code=code)
        except APIError:
            logger.warning("extraction_failure_status_not_persisted", extra={"job_id": str(job.id)})
        if isinstance(error, APIError):
            raise
        logger.error(
            "unexpected_extraction_failure type=%s job_id=%s", type(error).__name__, job.id
        )
        raise APIError(
            502, "extraction_failed", "Receipt extraction could not be completed. Please retry."
        ) from error
    # This is only a draft. No expense is created until POST /expenses.
    return ExtractionResponse(job=job, cached=False)


@router.get("/receipts/{receipt_id}/extraction", response_model=ExtractionJob, tags=["Extraction"])
async def extraction_status(receipt_id: UUID, repository: Repository):
    return await repository.latest_job(receipt_id)


@router.post("/expenses", response_model=Expense, status_code=201, tags=["Expenses"])
async def create_expense(
    fields: ExpenseCreate,
    response: Response,
    repository: Repository,
    idempotency_key: Annotated[
        UUID,
        Header(description="A new UUID per confirmed expense; reuse only for an identical retry"),
    ],
):
    expense, reused = await repository.create_expense(fields, idempotency_key)
    if reused:
        response.status_code = 200
    return expense


@router.get("/expenses", response_model=ExpensePage, tags=["Expenses"])
async def list_expenses(
    repository: Repository,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
    search: Annotated[str | None, Query(max_length=120)] = None,
    category: Category | None = None,
    currency: Currency | None = None,
    date_from: date | None = None,
    date_to: date | None = None,
):
    if date_from and date_to and date_from > date_to:
        raise APIError(422, "invalid_date_range", "date_from must not be after date_to.")
    items, total = await repository.list_expenses(
        limit=limit,
        offset=offset,
        search=search,
        category=category,
        currency=currency,
        start=date_from,
        end=date_to,
    )
    return ExpensePage(items=items, total=total, limit=limit, offset=offset)


@router.get("/expenses/{expense_id}", response_model=Expense, tags=["Expenses"])
async def get_expense(expense_id: UUID, repository: Repository):
    return await repository.get_expense(expense_id)


@router.put("/expenses/{expense_id}", response_model=Expense, tags=["Expenses"])
async def update_expense(expense_id: UUID, fields: ExpenseFields, repository: Repository):
    return await repository.update_expense(expense_id, fields)


@router.delete("/expenses/{expense_id}", status_code=204, tags=["Expenses"])
async def delete_expense(expense_id: UUID, repository: Repository):
    await repository.delete_expense(expense_id)
    return Response(status_code=204)


@router.get("/analytics", response_model=SpendingReport, tags=["Analytics"])
async def analytics(
    repository: Repository, period: Period = Period.THIS_MONTH, currency: Currency = "USD"
):
    today = datetime.now(UTC).date()
    selected = period_range(period, today)
    records = await repository.analytics_expenses(
        currency, selected.previous.start, selected.end_exclusive - timedelta(days=1)
    )
    return aggregate_expenses(records, period, currency, today)


# Parcours : authentification → limitation → compréhension OpenAI → lecture
# des dépenses du compte → calcul déterministe. Aucune écriture dans cette route.
@router.post("/ask-snap", tags=["Ask Snap"], response_model=AskResponse)
async def ask_snap(
    question: AskRequest,
    request: Request,
    repository: Repository,
    identity: Annotated[AuthenticatedUser, Depends(get_current_user)],
):
    if not question.message.strip():
        raise APIError(422, "ask_empty_question", "Type a question about your saved expenses.")
    planner = request.app.state.ask_planner
    if planner is None:
        raise APIError(503, "ask_not_configured", "Ask Snap is not configured on the server yet.")
    with request.app.state.ask_limiter.slot(str(identity.user.id)):
        today = datetime.now(UTC).date()
        plan = await planner.plan(question, today)
        # Une demande non prise en charge ne nécessite pas de lire les dépenses.
        expenses = (
            []
            if plan.intent in {"unsupported", "clarify"}
            else await load_owned_expenses(repository)
        )
        response = answer_question(plan, expenses, today, question.currency)
        return response
