"""Session routes for device_runtime API."""

from __future__ import annotations

from pydantic import BaseModel, Field
from fastapi import APIRouter, HTTPException

from device_runtime.api.session_manager import SessionOpenPayload, session_manager

router = APIRouter(prefix="/api/device/session", tags=["device-session"])


class OpenSessionRequest(BaseModel):
    session_code: str = Field(min_length=1, max_length=64)
    stream_url: str = Field(min_length=1)
    mirror_view: bool = False
    mode: str | None = None
    preview_source: str | None = None
    start_mode: str | None = None


class CloseSessionRequest(BaseModel):
    session_code: str | None = None


_MODE_TO_START_MODE = {
    "mobile_only": "MANUAL",
    "gimbal_manual": "MANUAL",
    "gimbal_follow": "AUTO_TRACK",
    "gimbal_template": "SMART_COMPOSE",
    "ai_auto_angle": "MANUAL",
    "ai_background": "MANUAL",
    "device_link": "MANUAL",
    "manual": "MANUAL",
    "auto_track": "AUTO_TRACK",
    "smart_compose": "SMART_COMPOSE",
}

_START_MODE_TO_CANONICAL_MODE = {
    "MANUAL": "gimbal_manual",
    "AUTO_TRACK": "gimbal_follow",
    "SMART_COMPOSE": "gimbal_template",
}


def _resolve_session_modes(mode: str | None, start_mode: str | None) -> tuple[str, str]:
    raw_mode = (mode or "").strip()
    raw_start_mode = (start_mode or "").strip()
    raw_value = raw_mode or raw_start_mode or "MANUAL"
    start = _MODE_TO_START_MODE.get(raw_value.lower())
    if start is None:
        raise ValueError(f"unsupported session mode: {raw_value}")
    canonical = raw_mode.lower() if raw_mode and raw_mode.lower() in _MODE_TO_START_MODE else ""
    if canonical not in {
        "mobile_only",
        "gimbal_manual",
        "gimbal_follow",
        "gimbal_template",
        "ai_auto_angle",
        "ai_background",
    }:
        canonical = _START_MODE_TO_CANONICAL_MODE[start]
    return canonical, start


def _resolve_preview_source(preview_source: str | None, stream_url: str) -> str:
    normalized = (preview_source or "").strip()
    if normalized:
        return normalized
    if stream_url.strip() == "mobile_push":
        return "phone_camera"
    return "device_stream"


@router.post("/open")
def open_session(payload: OpenSessionRequest) -> dict:
    try:
        mode, start_mode = _resolve_session_modes(payload.mode, payload.start_mode)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    preview_source = _resolve_preview_source(payload.preview_source, payload.stream_url)
    session = session_manager.open_session(
        SessionOpenPayload(
            session_code=payload.session_code,
            stream_url=payload.stream_url,
            mirror_view=payload.mirror_view,
            start_mode=start_mode,
            mode=mode,
            preview_source=preview_source,
        )
    )
    return {
        "success": True,
        "message": "session opened",
        "data": {
            "session_code": session.session_code,
            "stream_url": session.stream_url,
            "mirror_view": session.mirror_view,
            "mode": session.mode,
            "preview_source": session.preview_source,
            "start_mode": session.control_service.get_mode().value,
        },
    }


@router.post("/close")
def close_session(payload: CloseSessionRequest) -> dict:
    active_session = session_manager.current_session()
    if active_session is None:
        return {"success": True, "message": "session already closed", "data": {"closed": False}}
    if payload.session_code and payload.session_code != active_session.session_code:
        return {
            "success": False,
            "message": "session code mismatch",
            "error_code": "SESSION_CODE_MISMATCH",
        }
    closed = session_manager.close_session()
    return {"success": True, "message": "session closed", "data": {"closed": closed}}
