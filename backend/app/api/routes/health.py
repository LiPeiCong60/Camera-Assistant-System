"""Health check routes for backend service."""

from __future__ import annotations

from fastapi import APIRouter

from backend.app.core.config import get_settings
from backend.app.core.db import get_database_status

router = APIRouter(tags=["health"])


@router.get("/health")
def health_check() -> dict:
    settings = get_settings()
    db_status = get_database_status(settings.database_url)
    return {
        "success": True,
        "message": "ok",
        "data": {
            "service": settings.app_name,
            "environment": settings.environment,
            "version": settings.version,
            "database": db_status,
        },
    }
