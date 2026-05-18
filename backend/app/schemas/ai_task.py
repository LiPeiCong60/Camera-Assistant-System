"""AI task schemas."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any

from pydantic import Field, field_validator, model_validator

from backend.app.core.contract import (
    normalize_ai_response_payload,
    normalize_ai_task_type,
    normalize_target_box_norm,
)
from backend.app.schemas.base import SchemaModel


class AiTaskRead(SchemaModel):
    id: int
    task_code: str
    user_id: int
    session_id: int | None = None
    capture_id: int | None = None
    device_id: int | None = None
    task_type: str
    status: str
    provider_name: str | None = None
    request_payload: dict
    response_payload: dict | None = None
    result_summary: str | None = None
    result_score: Decimal | None = None
    recommended_pan_delta: Decimal | None = None
    recommended_tilt_delta: Decimal | None = None
    target_box_norm: dict[str, Any] | None = None
    error_message: str | None = None
    created_at: datetime
    updated_at: datetime
    finished_at: datetime | None = None

    @field_validator("task_type", mode="before")
    @classmethod
    def normalize_task_type_value(cls, value):
        return normalize_ai_task_type(value)

    @field_validator("target_box_norm", mode="before")
    @classmethod
    def normalize_target_box_value(cls, value):
        return normalize_target_box_norm(value)

    @field_validator("response_payload", mode="before")
    @classmethod
    def normalize_response_payload_value(cls, value):
        return normalize_ai_response_payload(value)

    @model_validator(mode="after")
    def populate_target_box_from_payload(self):
        if self.target_box_norm is None and isinstance(self.response_payload, dict):
            self.target_box_norm = normalize_target_box_norm(self.response_payload.get("target_box_norm"))
        return self


class AnalyzePhotoRequest(SchemaModel):
    session_id: int
    capture_id: int


class AnalyzeBackgroundRequest(SchemaModel):
    session_id: int
    capture_id: int
    device_id: int | None = None


class BatchPickRequest(SchemaModel):
    session_id: int
    capture_ids: list[int] = Field(..., min_length=2, max_length=9)


class BatchPickResult(SchemaModel):
    task: AiTaskRead
    best_capture_id: int | None = None
