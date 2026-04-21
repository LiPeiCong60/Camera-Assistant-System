"""Plan response schemas."""

from __future__ import annotations

from datetime import datetime

from pydantic import Field

from backend.app.schemas.base import SchemaModel


class PlanRead(SchemaModel):
    id: int
    plan_code: str
    name: str
    description: str | None = None
    price_cents: int
    currency: str
    billing_cycle_days: int
    capture_quota: int | None = None
    ai_task_quota: int | None = None
    feature_flags: dict
    status: str
    created_at: datetime
    updated_at: datetime


class PlanWriteRequest(SchemaModel):
    plan_code: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=100)
    description: str | None = None
    price_cents: int = Field(ge=0)
    currency: str = Field(min_length=3, max_length=3)
    billing_cycle_days: int = Field(gt=0)
    capture_quota: int | None = Field(default=None, ge=0)
    ai_task_quota: int | None = Field(default=None, ge=0)
    feature_flags: dict = Field(default_factory=dict)
    status: str = Field(pattern="^(active|inactive)$")
