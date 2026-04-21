"""Capture repository."""

from __future__ import annotations

from sqlalchemy import select

from backend.app.models.capture import Capture
from backend.app.repositories.base import Repository


class CaptureRepository(Repository[Capture]):
    model = Capture

    def list_by_session(self, session_id: int) -> list[Capture]:
        stmt = select(Capture).where(Capture.session_id == session_id).order_by(Capture.id.asc())
        return list(self.session.scalars(stmt))

    def get_for_user(self, user_id: int, capture_id: int) -> Capture | None:
        stmt = select(Capture).where(Capture.id == capture_id).where(Capture.user_id == user_id)
        return self.session.scalar(stmt)

    def list_by_user(self, user_id: int) -> list[Capture]:
        stmt = select(Capture).where(Capture.user_id == user_id).order_by(Capture.created_at.desc(), Capture.id.desc())
        return list(self.session.scalars(stmt))

    def list_by_user_and_ids(self, user_id: int, capture_ids: list[int]) -> list[Capture]:
        stmt = (
            select(Capture)
            .where(Capture.user_id == user_id)
            .where(Capture.id.in_(capture_ids))
            .order_by(Capture.id.asc())
        )
        return list(self.session.scalars(stmt))

    def list_all_captures(self) -> list[Capture]:
        stmt = select(Capture).order_by(Capture.created_at.desc(), Capture.id.desc())
        return list(self.session.scalars(stmt))
