"""Template ORM model."""

from __future__ import annotations

from sqlalchemy import BigInteger, Boolean, CheckConstraint, ForeignKey, Integer, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.app.models.base import Base, TimestampMixin


class Template(TimestampMixin, Base):
    __tablename__ = "templates"
    __table_args__ = (
        CheckConstraint("template_type IN ('pose', 'background', 'composition')", name="chk_templates_type"),
        CheckConstraint("status IN ('active', 'archived', 'deleted')", name="chk_templates_status"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    template_type: Mapped[str] = mapped_column(String(32), nullable=False, default="pose", server_default="pose")
    source_image_url: Mapped[str | None] = mapped_column(Text)
    preview_image_url: Mapped[str | None] = mapped_column(Text)
    template_data: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict, server_default="{}")
    is_recommended_default: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="FALSE",
    )
    recommended_sort_order: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default="0",
    )
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="active", server_default="active")

    user = relationship("User", back_populates="templates")
    capture_sessions = relationship("CaptureSession", back_populates="template")
