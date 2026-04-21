"""Base repository helpers."""

from __future__ import annotations

from typing import Generic, TypeVar

from sqlalchemy import Select, select
from sqlalchemy.orm import Session

from backend.app.models.base import Base

ModelT = TypeVar("ModelT", bound=Base)


class Repository(Generic[ModelT]):
    """Thin repository wrapper around SQLAlchemy Session."""

    model: type[ModelT]

    def __init__(self, session: Session) -> None:
        self.session = session

    def get(self, entity_id: int) -> ModelT | None:
        return self.session.get(self.model, entity_id)

    def add(self, entity: ModelT) -> ModelT:
        self.session.add(entity)
        return entity

    def list_all(self, *, limit: int = 100, offset: int = 0) -> list[ModelT]:
        stmt = self.base_query().offset(offset).limit(limit)
        return list(self.session.scalars(stmt))

    def base_query(self) -> Select[tuple[ModelT]]:
        return select(self.model)
