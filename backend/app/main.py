import asyncio
import logging
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from openai import AsyncOpenAI
from starlette.exceptions import HTTPException
from starlette.responses import JSONResponse

from .api import router
from .config import Settings
from .errors import APIError
from .middleware import BodySizeLimitMiddleware, RequestContextMiddleware
from .schemas import Health
from .services.ask_snap import AskLimiter, AskPlanner
from .services.extraction import OpenAIExtractor

logger = logging.getLogger(__name__)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings()

    @asynccontextmanager
    async def lifespan(app):
        logging.getLogger("httpx").setLevel(logging.WARNING)
        logging.getLogger("openai").setLevel(logging.WARNING)
        async with httpx.AsyncClient(timeout=20, limits=httpx.Limits(max_connections=50)) as http:
            client = (
                AsyncOpenAI(
                    api_key=settings.openai_api_key.get_secret_value(),
                    timeout=settings.openai_timeout_seconds,
                    max_retries=0,
                )
                if settings.openai_api_key
                else None
            )
            app.state.http = http
            app.state.image_processing_slots = asyncio.Semaphore(2)
            app.state.extractor = OpenAIExtractor(client, settings) if client else None
            # Réutilise le client OpenAI côté serveur : aucune clé dans Flutter.
            # Le limiteur vit pendant toute la durée de ce processus serveur.
            app.state.ask_planner = AskPlanner(client, settings) if client else None
            app.state.ask_limiter = AskLimiter()
            try:
                yield
            finally:
                if client:
                    await client.close()

    app = FastAPI(
        title="SnapExpense AI API",
        version="0.1.0",
        lifespan=lifespan,
        description="Authenticated receipt drafts, user-confirmed expenses, private receipt images, and currency-separated analytics. Flutter integration is intentionally separate.",
    )
    app.state.settings = settings
    app.add_middleware(BodySizeLimitMiddleware, maximum=settings.max_upload_bytes + 64 * 1024)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
        expose_headers=["X-Request-ID"],
    )
    app.add_middleware(RequestContextMiddleware)

    def payload(request, code, message):
        return {
            "error": {"code": code, "message": message},
            "request_id": getattr(request.state, "request_id", None),
        }

    @app.exception_handler(APIError)
    async def handle_api_error(request: Request, error: APIError):
        headers = {"WWW-Authenticate": "Bearer"} if error.status == 401 else None
        return JSONResponse(
            payload(request, error.code, error.message), status_code=error.status, headers=headers
        )

    @app.exception_handler(RequestValidationError)
    async def handle_validation(request: Request, error: RequestValidationError):
        body = payload(request, "validation_error", "Check the supplied fields.")
        # Do not echo uploaded bytes or sensitive request input in validation errors.
        body["fields"] = [
            {"location": list(item["loc"]), "message": item["msg"]} for item in error.errors()
        ]
        return JSONResponse(body, status_code=422)

    @app.exception_handler(HTTPException)
    async def handle_http_error(request: Request, error: HTTPException):
        return JSONResponse(
            payload(request, "http_error", str(error.detail)),
            status_code=error.status_code,
            headers=error.headers,
        )

    @app.exception_handler(Exception)
    async def handle_unexpected(request: Request, error: Exception):
        logger.error(
            "unhandled_api_error type=%s request_id=%s",
            type(error).__name__,
            getattr(request.state, "request_id", None),
        )
        return JSONResponse(
            payload(request, "internal_error", "The server could not complete this request."),
            status_code=500,
        )

    @app.get("/health", response_model=Health, tags=["Health"])
    async def health():
        return Health(status="ok")

    @app.get("/ready", tags=["Health"])
    async def ready(request: Request):
        missing = settings.missing_configuration()
        if missing:
            return JSONResponse({"status": "not_configured", "missing": missing}, status_code=503)
        headers = {
            "apikey": settings.supabase_service_role_key.get_secret_value(),
            "Authorization": f"Bearer {settings.supabase_service_role_key.get_secret_value()}",
        }
        try:
            results = await asyncio.gather(
                *[
                    request.app.state.http.get(
                        f"{settings.supabase_url}/rest/v1/{table}",
                        params={"select": "id", "limit": "0"},
                        headers=headers,
                    )
                    for table in ["receipts", "expenses", "extraction_jobs"]
                ],
                request.app.state.http.get(
                    f"{settings.supabase_url}/storage/v1/bucket/{settings.supabase_storage_bucket}",
                    headers=headers,
                ),
            )
            if (
                any(not result.is_success for result in results)
                or not isinstance(results[-1].json(), dict)
                or results[-1].json().get("public") is not False
                or not isinstance(results[-1].json().get("file_size_limit"), int)
                or not 0 < results[-1].json()["file_size_limit"] <= settings.max_upload_bytes
            ):
                raise ValueError("Supabase schema or private bucket not ready")
        except (httpx.RequestError, ValueError):
            return JSONResponse(
                {
                    "status": "not_ready",
                    "message": "Check Supabase credentials, migration, and private bucket configuration.",
                },
                status_code=503,
            )
        # No paid OpenAI call is made by health checks; account/model access is not verified here.
        return {"status": "ready", "supabase": "reachable", "openai": "configured_not_live_tested"}

    app.include_router(router)
    return app


app = create_app()
