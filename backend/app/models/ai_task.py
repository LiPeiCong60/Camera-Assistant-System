"""AI task ORM model."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import BigInteger, CheckConstraint, DateTime, ForeignKey, JSON, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.app.models.base import Base, TimestampMixin


class AiTask(TimestampMixin, Base):
    __tablename__ = "ai_tasks"
    __table_args__ = (
        CheckConstraint(
            "task_type IN ('analyze_photo', 'analyze_background', 'analyze_template', 'batch_pick', 'auto_angle', 'background_lock')",
            name="chk_ai_tasks_type",
        ),
        CheckConstraint(
            "status IN ('pending', 'running', 'succeeded', 'failed', 'cancelled')",
            name="chk_ai_tasks_status",
        ),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    task_code: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    session_id: Mapped[int | None] = mapped_column(ForeignKey("capture_sessions.id", ondelete="SET NULL"))
    capture_id: Mapped[int | None] = mapped_column(ForeignKey("captures.id", ondelete="SET NULL"))
    device_id: Mapped[int | None] = mapped_column(ForeignKey("devices.id", ondelete="SET NULL"))
    task_type: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="pending", server_default="pending")
    provider_name: Mapped[str | None] = mapped_column(String(100))
    request_payload: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict, server_default="{}")
    response_payload: Mapped[dict | None] = mapped_column(JSON)
    result_summary: Mapped[str | None] = mapped_column(Text)
    result_score: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    recommended_pan_delta: Mapped[Decimal | None] = mapped_column(Numeric(8, 2))
    recommended_tilt_delta: Mapped[Decimal | None] = mapped_column(Numeric(8, 2))
    target_box_norm: Mapped[list[float] | dict | None] = mapped_column(JSON)
    error_message: Mapped[str | None] = mapped_column(Text)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user = relationship("User", back_populates="ai_tasks")
    session = relationship("CaptureSession", back_populates="ai_tasks")
    capture = relationship("Capture", back_populates="ai_tasks")
    device = relationship("Device", back_populates="ai_tasks")
