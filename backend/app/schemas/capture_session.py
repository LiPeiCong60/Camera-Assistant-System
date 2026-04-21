"""Capture session schemas."""

from __future__ import annotations

from datetime import datetime

from pydantic import Field

from backend.app.schemas.base import SchemaModel


class CaptureSessionRead(SchemaModel):
    id: int
    session_code: str
    user_id: int
    device_id: int | None = None
    template_id: int | None = None
    mode: str
    status: str
    started_at: datetime
    ended_at: datetime | None = None
    metadata: dict = Field(default_factory=dict, validation_alias="session_metadata", serialization_alias="metadata")
    created_at: datetime
    updated_at: datetime


class CaptureSessionCreateRequest(SchemaModel):
    device_id: int | None = None
    template_id: int | None = None
    mode: str = "mobile_only"
    metadata: dict = Field(default_factory=dict)
