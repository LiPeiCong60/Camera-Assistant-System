"""Capture session repository."""

from __future__ import annotations

from sqlalchemy import select

from backend.app.models.capture_session import CaptureSession
from backend.app.repositories.base import Repository


class CaptureSessionRepository(Repository[CaptureSession]):
    model = CaptureSession

    def get_by_session_code(self, session_code: str) -> CaptureSession | None:
        stmt = select(CaptureSession).where(CaptureSession.session_code == session_code)
        return self.session.scalar(stmt)

    def get_for_user(self, user_id: int, session_id: int) -> CaptureSession | None:
        stmt = select(CaptureSession).where(CaptureSession.id == session_id).where(CaptureSession.user_id == user_id)
        return self.session.scalar(stmt)

    def list_by_user(self, user_id: int) -> list[CaptureSession]:
        stmt = (
            select(CaptureSession)
            .where(CaptureSession.user_id == user_id)
            .order_by(CaptureSession.started_at.desc(), CaptureSession.id.desc())
        )
        return list(self.session.scalars(stmt))
