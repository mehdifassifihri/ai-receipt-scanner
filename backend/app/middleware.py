import logging
import time
from uuid import uuid4

from starlette.responses import JSONResponse

logger = logging.getLogger("snapexpense.requests")


def error_content(scope, code: str, message: str):
    return {
        "error": {"code": code, "message": message},
        "request_id": scope.get("state", {}).get("request_id"),
    }


class RequestContextMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        request_id = str(uuid4())
        scope.setdefault("state", {})["request_id"] = request_id
        started = time.monotonic()

        async def send_with_context(message):
            if message["type"] == "http.response.start":
                message.setdefault("headers", []).append((b"x-request-id", request_id.encode()))
                message["headers"].append((b"x-content-type-options", b"nosniff"))
                logger.info(
                    "request method=%s path=%s status=%s duration_ms=%.1f request_id=%s",
                    scope["method"],
                    scope["path"],
                    message["status"],
                    (time.monotonic() - started) * 1000,
                    request_id,
                )
            await send(message)

        await self.app(scope, receive, send_with_context)


class BodySizeLimitMiddleware:
    """Bound the complete body before multipart parsing, including chunked uploads."""

    def __init__(self, app, maximum: int):
        self.app = app
        self.maximum = maximum

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["method"] not in {"POST", "PUT", "PATCH"}:
            return await self.app(scope, receive, send)
        headers = dict(scope.get("headers", []))
        try:
            declared = int(headers.get(b"content-length", b"0"))
        except ValueError:
            return await JSONResponse(
                error_content(scope, "invalid_content_length", "Invalid Content-Length."),
                status_code=400,
            )(scope, receive, send)
        if declared < 0 or declared > self.maximum:
            return await JSONResponse(
                error_content(scope, "request_too_large", "The request exceeds the upload limit."),
                status_code=413,
            )(scope, receive, send)
        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            body.extend(message.get("body", b""))
            if len(body) > self.maximum:
                return await JSONResponse(
                    error_content(
                        scope, "request_too_large", "The request exceeds the upload limit."
                    ),
                    status_code=413,
                )(scope, receive, send)
            if not message.get("more_body", False):
                break
        sent = False

        async def replay():
            nonlocal sent
            if not sent:
                sent = True
                return {"type": "http.request", "body": bytes(body), "more_body": False}
            return await receive()

        await self.app(scope, replay, send)
