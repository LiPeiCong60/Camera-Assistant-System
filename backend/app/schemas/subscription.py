"""Subscription schemas."""

from __future__ import annotations

from datetime import datetime

from backend.app.schemas.base import SchemaModel


class SubscriptionRead(SchemaModel):
    id: int
    user_id: int
    plan_id: int
    status: str
    started_at: datetime
    expires_at: datetime | None = None
    auto_renew: bool
    quota_snapshot: dict
    created_at: datetime
    updated_at: datetime
