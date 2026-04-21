"""Schemas for admin-managed AI provider configuration."""

from __future__ import annotations

from typing import Any

from pydantic import Field

from backend.app.schemas.base import SchemaModel


class AiProviderConfigWriteRequest(SchemaModel):
    provider_code: str = Field(min_length=1, max_length=64)
    vendor_name: str = Field(min_length=1, max_length=64)
    provider_format: str = Field(pattern="^(openai_compatible|anthropic_compatible|custom)$")
    display_name: str = Field(min_length=1, max_length=100)
    api_base_url: str | None = None
    api_key: str | None = None
    model_name: str | None = None
    enabled: bool = False
    is_default: bool = False
    notes: str | None = None
    extra_config: dict[str, Any] = Field(default_factory=dict)


class AiProviderConfigRead(SchemaModel):
    id: int
    provider_code: str
    vendor_name: str
    provider_format: str
    display_name: str
    api_base_url: str | None
    model_name: str | None
    enabled: bool
    is_default: bool
    has_api_key: bool
    masked_api_key: str | None
    notes: str | None
    extra_config: dict[str, Any]
