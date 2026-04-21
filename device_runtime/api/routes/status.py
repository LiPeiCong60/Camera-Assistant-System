"""Status routes for device_runtime API."""

from __future__ import annotations

from fastapi import APIRouter
from fastapi.responses import Response

from device_runtime.api.dependencies import require_session
from device_runtime.api.session_manager import session_manager

router = APIRouter(tags=["device-status"])


@router.get("/api/device/health")
def health_check() -> dict:
    active_session = session_manager.current_session()
    device_status = "online" if active_session is not None else "idle"
    session_code = active_session.session_code if active_session is not None else None
    return {
        "success": True,
        "message": "ok",
        "data": {
            "device_code": "DEV_RUNTIME_LOCAL",
            "status": device_status,
            "service_version": "0.1.0",
            "session_code": session_code,
        },
    }


@router.get("/api/device/status")
def get_status() -> dict:
    session = require_session()
    return {
        "success": True,
        "message": "ok",
        "data": session.build_status(),
    }


@router.get("/api/device/preview.jpg")
def get_preview_frame() -> Response:
    session = require_session()
    jpeg_bytes = session.get_preview_jpeg_bytes()
    return Response(
        content=jpeg_bytes,
        media_type="image/jpeg",
        headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
    )
