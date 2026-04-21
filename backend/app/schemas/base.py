"""Shared Pydantic schemas for backend API."""

from __future__ import annotations

from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict

DataT = TypeVar("DataT")


class SchemaModel(BaseModel):
    """Base schema with ORM attribute support."""

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)


class ApiResponse(BaseModel, Generic[DataT]):
    success: bool = True
    message: str = "ok"
    data: DataT


class ListData(BaseModel, Generic[DataT]):
    items: list[DataT]
