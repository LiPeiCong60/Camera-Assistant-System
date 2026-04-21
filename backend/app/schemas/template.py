"""Template schemas."""

from __future__ import annotations

from datetime import datetime

from pydantic import Field

from backend.app.schemas.base import SchemaModel


class TemplateRead(SchemaModel):
    id: int
    user_id: int
    name: str
    template_type: str
    source_image_url: str | None = None
    preview_image_url: str | None = None
    template_data: dict
    is_recommended_default: bool = False
    recommended_sort_order: int = 0
    status: str
    created_at: datetime
    updated_at: datetime


class TemplateCreateRequest(SchemaModel):
    name: str
    template_type: str = "pose"
    source_image_url: str | None = None
    preview_image_url: str | None = None
    template_data: dict = Field(default_factory=dict)


class RecommendedTemplateWriteRequest(SchemaModel):
    name: str
    template_type: str = "pose"
    source_image_url: str | None = None
    preview_image_url: str | None = None
    template_data: dict = Field(default_factory=dict)
    recommended_sort_order: int = 0
    status: str = "active"
