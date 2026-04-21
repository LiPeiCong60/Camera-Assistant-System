"""User repository."""

from __future__ import annotations

from sqlalchemy import select

from backend.app.models.user import User
from backend.app.repositories.base import Repository


class UserRepository(Repository[User]):
    model = User

    def get_by_user_code(self, user_code: str) -> User | None:
        stmt = select(User).where(User.user_code == user_code)
        return self.session.scalar(stmt)

    def get_by_phone(self, phone: str) -> User | None:
        stmt = select(User).where(User.phone == phone)
        return self.session.scalar(stmt)

    def get_by_email(self, email: str) -> User | None:
        stmt = select(User).where(User.email == email)
        return self.session.scalar(stmt)

    def list_users(self) -> list[User]:
        stmt = select(User).order_by(User.id.asc())
        return list(self.session.scalars(stmt))
