"""Stream routes for device_runtime API."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from device_runtime.api.dependencies import require_session

router = APIRouter(prefix="/api/device/stream", tags=["device-stream"])


class StartStreamRequest(BaseModel):
    stream_url: str = Field(min_length=1)


@router.post("/start")
def start_stream(payload: StartStreamRequest) -> dict:
    session = require_session()
    try:
        session.restart_stream(payload.stream_url)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {
        "success": True,
        "message": "stream started",
        "data": {
            "session_code": session.session_code,
            "stream_url": session.stream_url,
            "device_status": session.device_status,
        },
    }
