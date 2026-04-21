"""Top-level API router for backend service."""

from fastapi import APIRouter

from backend.app.api.routes.admin import router as admin_router
from backend.app.api.routes.health import router as health_router
from backend.app.api.routes.mobile import router as mobile_router

api_router = APIRouter(prefix="/api")
api_router.include_router(admin_router)
api_router.include_router(health_router)
api_router.include_router(mobile_router)
