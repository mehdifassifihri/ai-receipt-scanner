from datetime import date
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.config import Settings
from app.errors import APIError
from app.schemas import RawReceiptExtraction
from app.services.extraction import OpenAIExtractor, normalize_extraction


def raw(**updates):
    return RawReceiptExtraction(
        is_receipt=True,
        merchant="Starbucks",
        transaction_date="2026-10-18",
        amount="24.50",
        currency="mad",
        category="Food & Drinks",
        warnings=[],
        **updates,
    )


def test_decimal_conversion_is_exact():
    result = normalize_extraction(raw(), today=date(2026, 10, 18))
    assert result.fields.amount_in_cents == 2450
    assert result.fields.currency == "MAD"
    assert result.requires_review is True


def test_unknown_fields_never_become_fabricated_values():
    value = raw().model_copy(
        update={
            "merchant": " ",
            "amount": "1,245.67",
            "currency": "?",
            "transaction_date": "2026-99-99",
            "category": None,
        }
    )
    result = normalize_extraction(value)
    assert result.fields.model_dump() == {
        "merchant": None,
        "transaction_date": None,
        "amount_in_cents": None,
        "currency": None,
        "category": None,
    }
    assert len(result.warnings) == 5


@pytest.mark.parametrize("amount", ["0", "-20.00", "24.555", "$24.50", "1e3"])
def test_invalid_amounts_remain_unconfirmed(amount):
    assert (
        normalize_extraction(raw().model_copy(update={"amount": amount})).fields.amount_in_cents
        is None
    )


def test_non_receipts_are_rejected():
    with pytest.raises(APIError) as error:
        normalize_extraction(raw().model_copy(update={"is_receipt": False}))
    assert error.value.code == "not_a_readable_receipt"


async def test_openai_adapter_uses_image_schema_and_no_response_storage():
    parse = AsyncMock(return_value=SimpleNamespace(status="completed", output_parsed=raw()))
    extractor = OpenAIExtractor(
        SimpleNamespace(responses=SimpleNamespace(parse=parse)), Settings(_env_file=None)
    )
    result = await extractor.extract(b"jpeg-test-data")
    options = parse.call_args.kwargs
    assert options["store"] is False
    assert options["text_format"] is RawReceiptExtraction
    assert options["input"][0]["content"][1]["image_url"].startswith("data:image/jpeg;base64,")
    assert "untrusted" in options["instructions"]
    assert result.requires_review is True


async def test_refused_or_incomplete_output_is_not_saved_as_a_draft():
    parse = AsyncMock(return_value=SimpleNamespace(status="incomplete", output_parsed=None))
    extractor = OpenAIExtractor(
        SimpleNamespace(responses=SimpleNamespace(parse=parse)), Settings(_env_file=None)
    )
    with pytest.raises(APIError) as error:
        await extractor.extract(b"image")
    assert error.value.code == "extraction_incomplete"


async def test_actual_sdk_serializes_strict_schema_and_parses_a_mock_http_response():
    import json
    import time

    import httpx
    from openai import AsyncOpenAI

    calls = []

    def handle(request):
        calls.append(request)
        body = json.loads(request.content)
        assert request.url.path == "/v1/responses"
        assert body["store"] is False
        assert body["text"]["format"]["strict"] is True
        schema = body["text"]["format"]["schema"]
        assert schema["additionalProperties"] is False
        assert set(schema["required"]) == set(RawReceiptExtraction.model_fields)
        return httpx.Response(
            200,
            json={
                "id": "resp_test",
                "object": "response",
                "created_at": int(time.time()),
                "status": "completed",
                "model": "gpt-5-mini",
                "output": [
                    {
                        "id": "msg_test",
                        "type": "message",
                        "role": "assistant",
                        "status": "completed",
                        "content": [
                            {
                                "type": "output_text",
                                "text": raw().model_dump_json(),
                                "annotations": [],
                            }
                        ],
                    }
                ],
            },
        )

    async with AsyncOpenAI(
        api_key="sk-test-only",
        max_retries=0,
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handle)),
    ) as client:
        extractor = OpenAIExtractor(client, Settings(_env_file=None))
        result = await extractor.extract(b"jpeg-test")
    assert len(calls) == 1
    assert result.fields.amount_in_cents == 2450


async def test_invalid_provider_output_is_sanitized():
    parse = AsyncMock(side_effect=ValueError("sensitive invalid response content"))
    extractor = OpenAIExtractor(
        SimpleNamespace(responses=SimpleNamespace(parse=parse)), Settings(_env_file=None)
    )
    with pytest.raises(APIError) as error:
        await extractor.extract(b"image")
    assert error.value.code == "invalid_extraction_result"
    assert "sensitive" not in error.value.message
