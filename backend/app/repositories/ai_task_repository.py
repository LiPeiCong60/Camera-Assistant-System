"""AI task repository."""

from __future__ import annotations

from sqlalchemy import select

from backend.app.models.ai_task import AiTask
from backend.app.repositories.base import Repository


class AiTaskRepository(Repository[AiTask]):
    model = AiTask

    def get_by_task_code(self, task_code: str) -> AiTask | None:
        stmt = select(AiTask).where(AiTask.task_code == task_code)
        return self.session.scalar(stmt)

    def get_for_user(self, user_id: int, task_id: int) -> AiTask | None:
        stmt = select(AiTask).where(AiTask.id == task_id).where(AiTask.user_id == user_id)
        return self.session.scalar(stmt)

    def list_all_tasks(self) -> list[AiTask]:
        stmt = select(AiTask).order_by(AiTask.created_at.desc(), AiTask.id.desc())
        return list(self.session.scalars(stmt))
