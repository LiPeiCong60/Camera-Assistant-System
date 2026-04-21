"""AI application routes for device_runtime API."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from device_runtime.api.dependencies import require_session

router = APIRouter(prefix="/api/device/ai", tags=["device-ai"])


class ApplyAngleRequest(BaseModel):
    task_type: str
    recommended_pan_delta: float
    recommended_tilt_delta: float
    summary: str | None = None
    score: float | None = None


class ApplyLockRequest(BaseModel):
    task_type: str
    recommended_pan_delta: float
    recommended_tilt_delta: float
    target_box_norm: list[float] | tuple[float, float, float, float] | None = None
    summary: str | None = None
    score: float | None = None


@router.post("/apply-angle")
def apply_angle(payload: ApplyAngleRequest) -> dict:
    session = require_session()
    if payload.task_type != "auto_angle":
        raise HTTPException(status_code=400, detail=f"unsupported task_type: {payload.task_type}")

    pan_delta = max(-20.0, min(20.0, float(payload.recommended_pan_delta)))
    tilt_delta = max(-15.0, min(15.0, float(payload.recommended_tilt_delta)))

    try:
        session.control_service.move_relative(pan_delta, tilt_delta)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    pan, tilt = session.control_service.get_current_angles(prefer_feedback=True)
    return {
        "success": True,
        "message": "ai angle applied",
        "data": {
            "task_type": payload.task_type,
            "applied_pan_delta": round(pan_delta, 3),
            "applied_tilt_delta": round(tilt_delta, 3),
            "summary": payload.summary,
            "score": payload.score,
            "current_pan": round(float(pan), 3),
            "current_tilt": round(float(tilt), 3),
        },
    }


@router.post("/apply-lock")
def apply_lock(payload: ApplyLockRequest) -> dict:
    session = require_session()
    if payload.task_type != "background_lock":
        raise HTTPException(status_code=400, detail=f"unsupported task_type: {payload.task_type}")

    try:
        pan, tilt = session.apply_ai_lock(
            recommended_pan_delta=payload.recommended_pan_delta,
            recommended_tilt_delta=payload.recommended_tilt_delta,
            target_box_norm=payload.target_box_norm,
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {
        "success": True,
        "message": "ai lock applied",
        "data": {
            "task_type": payload.task_type,
            "summary": payload.summary,
            "score": payload.score,
            "current_pan": round(float(pan), 3),
            "current_tilt": round(float(tilt), 3),
            "ai_lock_status": {
                "enabled": session.runtime_state.ai_lock_mode_enabled,
                "fit_score": session.runtime_state.ai_lock_fit_score,
                "target_box_norm": session.runtime_state.ai_lock_target_box_norm,
            },
        },
    }
