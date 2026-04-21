"""User schemas."""

from __future__ import annotations

from datetime import datetime

from pydantic import Field

from backend.app.schemas.base import SchemaModel


class UserRead(SchemaModel):
    id: int
    user_code: str
    phone: str | None = None
    email: str | None = None
    display_name: str
    avatar_url: str | None = None
    role: str
    status: str
    current_plan_id: int | None = None
    current_plan_code: str | None = None
    current_plan_name: str | None = None
    current_subscription_status: str | None = None
    current_subscription_expires_at: datetime | None = None
    last_login_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class UserCreateRequest(SchemaModel):
    user_code: str
    phone: str | None = None
    email: str | None = None
    password: str = Field(min_length=6, max_length=128)
    display_name: str
    avatar_url: str | None = None
    role: str = "user"
    status: str = "active"
    current_plan_id: int | None = Field(default=None, ge=1)


class UserUpdateRequest(SchemaModel):
    user_code: str
    phone: str | None = None
    email: str | None = None
    password: str | None = Field(default=None, min_length=6, max_length=128)
    display_name: str
    avatar_url: str | None = None
    role: str = "user"
    status: str = "active"
    current_plan_id: int | None = Field(default=None, ge=1)
