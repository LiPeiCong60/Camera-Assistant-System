"""Capture session ORM model."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import BigInteger, CheckConstraint, DateTime, ForeignKey, JSON, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.app.models.base import Base, TimestampMixin


class CaptureSession(TimestampMixin, Base):
    __tablename__ = "capture_sessions"
    __table_args__ = (
        CheckConstraint(
            "mode IN ('mobile_only', 'device_link', 'MANUAL', 'AUTO_TRACK', 'SMART_COMPOSE')",
            name="chk_capture_sessions_mode",
        ),
        CheckConstraint("status IN ('opened', 'closed', 'cancelled')", name="chk_capture_sessions_status"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    session_code: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    device_id: Mapped[int | None] = mapped_column(ForeignKey("devices.id", ondelete="SET NULL"))
    template_id: Mapped[int | None] = mapped_column(ForeignKey("templates.id", ondelete="SET NULL"))
    mode: Mapped[str] = mapped_column(String(32), nullable=False, default="mobile_only", server_default="mobile_only")
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="opened", server_default="opened")
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    session_metadata: Mapped[dict] = mapped_column("metadata", JSON, nullable=False, default=dict, server_default="{}")

    user = relationship("User", back_populates="capture_sessions")
    device = relationship("Device", back_populates="capture_sessions")
    template = relationship("Template", back_populates="capture_sessions")
    captures = relationship("Capture", back_populates="session")
    ai_tasks = relationship("AiTask", back_populates="session")
