"""Admin statistics schemas."""

from __future__ import annotations

from backend.app.schemas.base import SchemaModel


class OverviewStatisticsRead(SchemaModel):
    user_count: int
    plan_count: int
    capture_count: int
    ai_task_count: int
