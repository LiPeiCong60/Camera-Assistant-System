"""FastAPI dependencies for device_runtime API."""

from __future__ import annotations

from fastapi import HTTPException

from device_runtime.api.session_manager import DeviceSessionContext, session_manager


def require_session() -> DeviceSessionContext:
    session = session_manager.current_session()
    if session is None:
        raise HTTPException(status_code=409, detail="device session is not opened")
    return session
