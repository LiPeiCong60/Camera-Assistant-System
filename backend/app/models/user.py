"""User ORM model."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import BigInteger, CheckConstraint, DateTime, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.app.models.base import Base, TimestampMixin


class User(TimestampMixin, Base):
    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint("role IN ('user', 'admin')", name="chk_users_role"),
        CheckConstraint("status IN ('active', 'inactive', 'disabled')", name="chk_users_status"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_code: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    phone: Mapped[str | None] = mapped_column(String(32))
    email: Mapped[str | None] = mapped_column(String(255))
    password_hash: Mapped[str | None] = mapped_column(Text)
    display_name: Mapped[str] = mapped_column(String(100), nullable=False)
    avatar_url: Mapped[str | None] = mapped_column(Text)
    role: Mapped[str] = mapped_column(String(32), nullable=False, default="user", server_default="user")
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="active", server_default="active")
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    subscriptions = relationship("UserSubscription", back_populates="user")
    devices = relationship("Device", back_populates="user")
    templates = relationship("Template", back_populates="user")
    capture_sessions = relationship("CaptureSession", back_populates="user")
    captures = relationship("Capture", back_populates="user")
    ai_tasks = relationship("AiTask", back_populates="user")
