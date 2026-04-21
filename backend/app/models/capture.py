"""Capture ORM model."""

from __future__ import annotations

from decimal import Decimal

from sqlalchemy import BigInteger, Boolean, CheckConstraint, ForeignKey, Integer, JSON, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.app.models.base import Base, TimestampMixin


class Capture(TimestampMixin, Base):
    __tablename__ = "captures"
    __table_args__ = (
        CheckConstraint(
            "capture_type IN ('single', 'photo', 'burst', 'best', 'background')",
            name="chk_captures_type",
        ),
        CheckConstraint(
            "(width IS NULL OR width > 0) AND (height IS NULL OR height > 0)",
            name="chk_captures_dimensions",
        ),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    session_id: Mapped[int] = mapped_column(ForeignKey("capture_sessions.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    capture_type: Mapped[str] = mapped_column(String(32), nullable=False, default="single", server_default="single")
    file_url: Mapped[str] = mapped_column(Text, nullable=False)
    thumbnail_url: Mapped[str | None] = mapped_column(Text)
    width: Mapped[int | None] = mapped_column(Integer)
    height: Mapped[int | None] = mapped_column(Integer)
    storage_provider: Mapped[str] = mapped_column(String(32), nullable=False, default="local", server_default="local")
    is_ai_selected: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    score: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    capture_metadata: Mapped[dict] = mapped_column("metadata", JSON, nullable=False, default=dict, server_default="{}")

    session = relationship("CaptureSession", back_populates="captures")
    user = relationship("User", back_populates="captures")
    ai_tasks = relationship("AiTask", back_populates="capture")
