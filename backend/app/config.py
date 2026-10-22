from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

from pydantic import AliasChoices, Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parents[1] / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
        populate_by_name=True,
    )
    app_env: Literal["development", "production", "test"] = "development"
    supabase_url: str | None = None
    supabase_publishable_key: SecretStr | None = Field(
        default=None,
        validation_alias=AliasChoices("SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY"),
    )
    supabase_service_role_key: SecretStr | None = None
    supabase_storage_bucket: str = Field(default="receipts", pattern=r"^[a-z0-9_-]+$")
    openai_api_key: SecretStr | None = None
    openai_model: str = "gpt-5-mini"
    ask_snap_model: str = "gpt-5-mini"
    openai_reasoning_effort: Literal["minimal", "low", "medium", "high"] | None = "low"
    openai_timeout_seconds: float = Field(default=45, ge=5, le=90)
    extraction_daily_limit: int = Field(default=50, ge=1, le=1000)
    max_upload_bytes: int = Field(default=6 * 1024 * 1024, ge=1024, le=6 * 1024 * 1024)
    cors_origins: list[str] = []

    @field_validator(
        "supabase_url",
        "supabase_publishable_key",
        "supabase_service_role_key",
        "openai_api_key",
        "openai_reasoning_effort",
        mode="before",
    )
    @classmethod
    def empty_is_unset(cls, value):
        return None if isinstance(value, str) and not value.strip() else value

    @field_validator("supabase_url")
    @classmethod
    def valid_supabase_url(cls, value):
        if value is None:
            return None
        parts = urlsplit(value)
        if parts.scheme not in {"https", "http"} or not parts.hostname:
            raise ValueError("SUPABASE_URL must be an HTTP(S) project URL")
        if (
            parts.username
            or parts.password
            or parts.query
            or parts.fragment
            or parts.path not in {"", "/"}
        ):
            raise ValueError("SUPABASE_URL must not contain credentials, paths, or query strings")
        return value.rstrip("/")

    @model_validator(mode="after")
    def production_https(self):
        if (
            self.app_env == "production"
            and self.supabase_url
            and not self.supabase_url.startswith("https://")
        ):
            raise ValueError("Production Supabase connections must use HTTPS")
        return self

    def missing_configuration(self) -> list[str]:
        return [
            name
            for name, value in {
                "SUPABASE_URL": self.supabase_url,
                "SUPABASE_PUBLISHABLE_KEY": self.supabase_publishable_key,
                "SUPABASE_SERVICE_ROLE_KEY": self.supabase_service_role_key,
                "OPENAI_API_KEY": self.openai_api_key,
            }.items()
            if not value
        ]
