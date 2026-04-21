"""Plan repository."""

from __future__ import annotations

from sqlalchemy import delete, func, select

from backend.app.models.plan import Plan
from backend.app.models.user_subscription import UserSubscription
from backend.app.repositories.base import Repository


class PlanRepository(Repository[Plan]):
    model = Plan

    def list_active(self) -> list[Plan]:
        stmt = select(Plan).where(Plan.status == "active").order_by(Plan.id.asc())
        return list(self.session.scalars(stmt))

    def list_all_plans(self) -> list[Plan]:
        stmt = select(Plan).order_by(Plan.id.asc())
        return list(self.session.scalars(stmt))

    def get_by_plan_code(self, plan_code: str) -> Plan | None:
        stmt = select(Plan).where(Plan.plan_code == plan_code)
        return self.session.scalar(stmt)

    def has_subscriptions(self, plan_id: int) -> bool:
        stmt = select(func.count()).select_from(UserSubscription).where(UserSubscription.plan_id == plan_id)
        return bool(self.session.scalar(stmt))

    def has_active_subscriptions(self, plan_id: int) -> bool:
        stmt = (
            select(func.count())
            .select_from(UserSubscription)
            .where(
                UserSubscription.plan_id == plan_id,
                UserSubscription.status == "active",
            )
        )
        return bool(self.session.scalar(stmt))

    def delete_inactive_subscriptions(self, plan_id: int) -> int:
        stmt = delete(UserSubscription).where(
            UserSubscription.plan_id == plan_id,
            UserSubscription.status != "active",
        )
        result = self.session.execute(stmt)
        return int(result.rowcount or 0)
