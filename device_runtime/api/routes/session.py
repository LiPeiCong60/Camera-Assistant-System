"""Session routes for device_runtime API."""

from __future__ import annotations

from pydantic import BaseModel, Field
from fastapi import APIRouter

from device_runtime.api.session_manager import SessionOpenPayload, session_manager

router = APIRouter(prefix="/api/device/session", tags=["device-session"])


class OpenSessionRequest(BaseModel):
    session_code: str = Field(min_length=1, max_length=64)
    stream_url: str = Field(min_length=1)
    mirror_view: bool = False
    start_mode: str = "MANUAL"


class CloseSessionRequest(BaseModel):
    session_code: str | None = None


@router.post("/open")
def open_session(payload: OpenSessionRequest) -> dict:
    session = session_manager.open_session(
        SessionOpenPayload(
            session_code=payload.session_code,
            stream_url=payload.stream_url,
            mirror_view=payload.mirror_view,
            start_mode=payload.start_mode,
        )
    )
    return {
        "success": True,
        "message": "session opened",
        "data": {
            "session_code": session.session_code,
            "stream_url": session.stream_url,
            "mirror_view": session.mirror_view,
            "mode": session.control_service.get_mode().value,
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
