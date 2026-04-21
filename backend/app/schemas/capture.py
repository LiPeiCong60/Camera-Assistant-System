"""Capture schemas."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from pydantic import Field

from backend.app.schemas.base import SchemaModel


class CaptureRead(SchemaModel):
    id: int
    session_id: int
    user_id: int
    capture_type: str
    file_url: str
    thumbnail_url: str | None = None
    width: int | None = None
    height: int | None = None
    storage_provider: str
    is_ai_selected: bool
    score: Decimal | None = None
    metadata: dict = Field(default_factory=dict, validation_alias="capture_metadata", serialization_alias="metadata")
    created_at: datetime
    updated_at: datetime


class CaptureCreateRequest(SchemaModel):
    session_id: int
    capture_type: str = "single"
    file_url: str
    thumbnail_url: str | None = None
    width: int | None = None
    height: int | None = None
    storage_provider: str = "local"
    is_ai_selected: bool = False
    score: Decimal | None = None
    metadata: dict = Field(default_factory=dict)


class CaptureUploadRead(SchemaModel):
    file_url: str
    storage_provider: str
    storage_path: str
    relative_path: str
    original_filename: str
    content_type: str | None = None
