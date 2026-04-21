"""AI provider configuration model."""

from __future__ import annotations

from sqlalchemy import JSON, Boolean, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from backend.app.models.base import Base, TimestampMixin


class AiProviderConfig(TimestampMixin, Base):
    __tablename__ = "ai_provider_configs"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    provider_code: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    vendor_name: Mapped[str] = mapped_column(String(64), nullable=False, default="custom", server_default="custom")
    provider_format: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default="openai_compatible",
        server_default="openai_compatible",
    )
    display_name: Mapped[str] = mapped_column(String(100), nullable=False)
    api_base_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    api_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    model_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    extra_config: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
