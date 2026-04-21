"""Plan ORM model."""

from __future__ import annotations

from sqlalchemy import BigInteger, CheckConstraint, Integer, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.app.models.base import Base, TimestampMixin


class Plan(TimestampMixin, Base):
    __tablename__ = "plans"
    __table_args__ = (
        CheckConstraint("price_cents >= 0", name="chk_plans_price"),
        CheckConstraint("billing_cycle_days > 0", name="chk_plans_cycle"),
        CheckConstraint("status IN ('active', 'inactive')", name="chk_plans_status"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    plan_code: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    price_cents: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default="CNY", server_default="CNY")
    billing_cycle_days: Mapped[int] = mapped_column(Integer, nullable=False, default=30, server_default="30")
    capture_quota: Mapped[int | None] = mapped_column(Integer)
    ai_task_quota: Mapped[int | None] = mapped_column(Integer)
    feature_flags: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict, server_default="{}")
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="active", server_default="active")

    subscriptions = relationship("UserSubscription", back_populates="plan")
