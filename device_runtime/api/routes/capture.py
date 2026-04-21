"""Capture routes for device_runtime API."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from device_runtime.api.dependencies import require_session

router = APIRouter(prefix="/api/device/capture", tags=["device-capture"])


class TriggerCaptureRequest(BaseModel):
    reason: str = "manual"


@router.post("/trigger")
def trigger_capture(payload: TriggerCaptureRequest) -> dict:
    session = require_session()
    try:
        result = session.trigger_capture(reason=payload.reason)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {
        "success": True,
        "message": "capture triggered",
        "data": {
            "reason": payload.reason,
            "capture_path": result.path,
        },
    }
