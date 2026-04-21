"""AI task schemas."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal

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
    target_box_norm: list[float] | dict | None = None
    error_message: str | None = None
    created_at: datetime
    updated_at: datetime
    finished_at: datetime | None = None


class AnalyzePhotoRequest(SchemaModel):
    session_id: int
    capture_id: int


class AnalyzeBackgroundRequest(SchemaModel):
    session_id: int
    capture_id: int
    device_id: int | None = None


class BatchPickRequest(SchemaModel):
    session_id: int
    capture_ids: list[int]


class BatchPickResult(SchemaModel):
    task: AiTaskRead
    best_capture_id: int | None = None
