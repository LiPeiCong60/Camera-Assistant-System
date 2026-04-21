"""Template repository."""

from __future__ import annotations

from sqlalchemy import or_, select

from backend.app.models.template import Template
from backend.app.repositories.base import Repository


class TemplateRepository(Repository[Template]):
    model = Template

    def list_by_user(self, user_id: int) -> list[Template]:
        stmt = (
            select(Template)
            .where(Template.user_id == user_id)
            .where(Template.is_recommended_default.is_(False))
            .where(Template.status != "deleted")
            .order_by(Template.id.desc())
        )
        return list(self.session.scalars(stmt))

    def list_available_for_user(self, user_id: int) -> list[Template]:
        stmt = (
            select(Template)
            .where(
                or_(
                    Template.user_id == user_id,
                    Template.is_recommended_default.is_(True),
                )
            )
            .where(Template.status != "deleted")
            .order_by(
                Template.is_recommended_default.desc(),
                Template.recommended_sort_order.asc(),
                Template.id.desc(),
            )
        )
        return list(self.session.scalars(stmt))

    def list_recommended_defaults(self) -> list[Template]:
        stmt = (
            select(Template)
            .where(Template.is_recommended_default.is_(True))
            .where(Template.status != "deleted")
            .order_by(Template.recommended_sort_order.asc(), Template.id.desc())
        )
        return list(self.session.scalars(stmt))

    def get_for_user(self, user_id: int, template_id: int) -> Template | None:
        stmt = (
            select(Template)
            .where(Template.id == template_id)
            .where(Template.user_id == user_id)
            .where(Template.is_recommended_default.is_(False))
            .where(Template.status != "deleted")
        )
        return self.session.scalar(stmt)

    def get_accessible_for_user(self, user_id: int, template_id: int) -> Template | None:
        stmt = (
            select(Template)
            .where(Template.id == template_id)
            .where(
                or_(
                    Template.user_id == user_id,
                    Template.is_recommended_default.is_(True),
                )
            )
            .where(Template.status != "deleted")
        )
        return self.session.scalar(stmt)

    def get_recommended_default(self, template_id: int) -> Template | None:
        stmt = (
            select(Template)
            .where(Template.id == template_id)
            .where(Template.is_recommended_default.is_(True))
            .where(Template.status != "deleted")
        )
        return self.session.scalar(stmt)
