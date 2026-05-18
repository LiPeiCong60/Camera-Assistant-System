"""Capture schemas."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from pydantic import Field, model_validator

from backend.app.core.contract import (
    extract_capture_media_fields,
    normalize_capture_metadata,
    normalize_capture_type,
)
from backend.app.schemas.ai_task import AiTaskRead
from backend.app.schemas.base import SchemaModel


class CaptureRead(SchemaModel):
    id: int
    session_id: int
    user_id: int
    capture_type: str
    media_type: str | None = None
    file_url: str
    thumbnail_url: str | None = None
    width: int | None = None
    height: int | None = None
    duration_ms: int | None = None
    storage_provider: str
    local_album_saved: bool | None = None
    is_ai_selected: bool
    score: Decimal | None = None
    metadata: dict = Field(default_factory=dict, validation_alias="capture_metadata", serialization_alias="metadata")
    latest_ai_task: AiTaskRead | None = None
    created_at: datetime
    updated_at: datetime

    @model_validator(mode="after")
    def populate_media_fields(self):
        raw_capture_type = self.capture_type
        media_fields = extract_capture_media_fields(self.metadata, capture_type=raw_capture_type)
        self.capture_type = normalize_capture_type(raw_capture_type)
        if self.media_type is None:
            self.media_type = media_fields["media_type"]
        if self.duration_ms is None:
            self.duration_ms = media_fields["duration_ms"]
        if self.local_album_saved is None:
            self.local_album_saved = media_fields["local_album_saved"]
        self.metadata = normalize_capture_metadata(
            self.metadata,
            capture_type=raw_capture_type,
            media_type=self.media_type,
            duration_ms=self.duration_ms,
            local_album_saved=self.local_album_saved,
        )
        return self


class CaptureCreateRequest(SchemaModel):
    session_id: int
    capture_type: str = "single"
    media_type: str | None = None
    file_url: str
    thumbnail_url: str | None = None
    width: int | None = None
    height: int | None = None
    duration_ms: int | None = Field(default=None, ge=0)
    storage_provider: str = "local"
    local_album_saved: bool | None = None
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
