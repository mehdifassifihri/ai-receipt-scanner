import pytest
from pydantic import ValidationError

from app.config import Settings
from app.middleware import BodySizeLimitMiddleware


async def test_chunked_body_limit_runs_before_parser_or_endpoint():
    called = False
    messages = iter(
        [
            {"type": "http.request", "body": b"a" * 40, "more_body": True},
            {"type": "http.request", "body": b"b" * 40, "more_body": False},
        ]
    )
    output = []

    async def child(_scope, _receive, _send):
        nonlocal called
        called = True

    async def receive():
        return next(messages)

    async def send(message):
        output.append(message)

    middleware = BodySizeLimitMiddleware(child, maximum=64)
    await middleware({"type": "http", "method": "POST", "headers": [], "state": {}}, receive, send)
    assert not called
    assert output[0]["status"] == 413


def test_secrets_are_redacted_and_production_rejects_plain_http():
    config = Settings(
        _env_file=None,
        openai_api_key="secret-value",
        supabase_url=None,
        supabase_publishable_key=None,
        supabase_service_role_key=None,
    )
    assert "secret-value" not in repr(config)
    with pytest.raises(ValidationError):
        Settings(_env_file=None, app_env="production", supabase_url="http://project.example")
    for invalid in [
        "https://user:password@project.example",
        "https://project.example/path",
        "https://project.example?key=secret",
    ]:
        with pytest.raises(ValidationError):
            Settings(_env_file=None, supabase_url=invalid)
