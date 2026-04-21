"""User subscription repository."""

from __future__ import annotations

from sqlalchemy import desc, select
from sqlalchemy.orm import selectinload

from backend.app.models.user_subscription import UserSubscription
from backend.app.repositories.base import Repository


class UserSubscriptionRepository(Repository[UserSubscription]):
    model = UserSubscription

    def get_current_for_user(self, user_id: int) -> UserSubscription | None:
        stmt = (
            select(UserSubscription)
            .options(selectinload(UserSubscription.plan))
            .where(
                UserSubscription.user_id == user_id,
                UserSubscription.status == "active",
            )
            .order_by(
                desc(UserSubscription.started_at),
                desc(UserSubscription.id),
            )
        )
        return self.session.scalar(stmt)

    def get_current_for_users(self, user_ids: list[int]) -> dict[int, UserSubscription]:
        if not user_ids:
            return {}

        stmt = (
            select(UserSubscription)
            .options(selectinload(UserSubscription.plan))
            .where(
                UserSubscription.user_id.in_(user_ids),
                UserSubscription.status == "active",
            )
            .order_by(
                UserSubscription.user_id.asc(),
                desc(UserSubscription.started_at),
                desc(UserSubscription.id),
            )
        )

        current_map: dict[int, UserSubscription] = {}
        for item in self.session.scalars(stmt):
            current_map.setdefault(int(item.user_id), item)
        return current_map
