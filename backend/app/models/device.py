"""Device ORM model."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import BigInteger, Boolean, CheckConstraint, DateTime, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.app.models.base import Base, TimestampMixin


class Device(TimestampMixin, Base):
    __tablename__ = "devices"
    __table_args__ = (
        CheckConstraint("device_type IN ('raspberry_pi')", name="chk_devices_type"),
        CheckConstraint("status IN ('offline', 'online', 'busy', 'disabled')", name="chk_devices_status"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    device_code: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    device_name: Mapped[str] = mapped_column(String(100), nullable=False)
    device_type: Mapped[str] = mapped_column(String(32), nullable=False, default="raspberry_pi", server_default="raspberry_pi")
    serial_number: Mapped[str | None] = mapped_column(String(128))
    local_ip: Mapped[str | None] = mapped_column(String(64))
    control_base_url: Mapped[str | None] = mapped_column(Text)
    firmware_version: Mapped[str | None] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="offline", server_default="offline")
    is_online: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user = relationship("User", back_populates="devices")
    capture_sessions = relationship("CaptureSession", back_populates="device")
    ai_tasks = relationship("AiTask", back_populates="device")
