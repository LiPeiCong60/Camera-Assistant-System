"""Authentication schemas."""

from __future__ import annotations

from pydantic import Field

from backend.app.schemas.base import SchemaModel


class LoginRequest(SchemaModel):
    phone: str
    password: str


class RegisterRequest(SchemaModel):
    phone: str = Field(min_length=1, max_length=32)
    password: str = Field(min_length=6, max_length=128)
    display_name: str = Field(min_length=1, max_length=100)


class AuthUserSummary(SchemaModel):
    id: int
    display_name: str
    role: str
    status: str


class LoginResponse(SchemaModel):
    access_token: str
    token_type: str = "bearer"
    user: AuthUserSummary
