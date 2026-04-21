"""Control routes for device_runtime API."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from device_runtime.api.dependencies import require_session
from device_runtime.mode_manager import ControlMode

router = APIRouter(prefix="/api/device/control", tags=["device-control"])


class ManualMoveRequest(BaseModel):
    action: str | None = None
    pan_delta: float | None = None
    tilt_delta: float | None = None


class ModeRequest(BaseModel):
    mode: str


class FollowModeRequest(BaseModel):
    follow_mode: str


@router.post("/manual-move")
def manual_move(payload: ManualMoveRequest) -> dict:
    session = require_session()
    try:
        if payload.pan_delta is not None or payload.tilt_delta is not None:
            session.control_service.move_relative(
                float(payload.pan_delta or 0.0),
                float(payload.tilt_delta or 0.0),
            )
        elif payload.action:
            session.control_service.manual_move(payload.action)
        else:
            raise ValueError("either action or pan_delta/tilt_delta is required")
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    pan, tilt = session.control_service.get_current_angles(prefer_feedback=True)
    return {
        "success": True,
        "message": "manual move applied",
        "data": {
            "current_pan": round(float(pan), 3),
            "current_tilt": round(float(tilt), 3),
        },
    }


@router.post("/mode")
def set_mode(payload: ModeRequest) -> dict:
    session = require_session()
    try:
        session.control_service.set_mode(ControlMode(payload.mode))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "success": True,
        "message": "mode updated",
        "data": {"mode": session.control_service.get_mode().value},
    }


@router.post("/home")
def home() -> dict:
    session = require_session()
    try:
        session.control_service.home()
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    pan, tilt = session.control_service.get_current_angles(prefer_feedback=True)
    return {
        "success": True,
        "message": "gimbal homed",
        "data": {
            "current_pan": round(float(pan), 3),
            "current_tilt": round(float(tilt), 3),
        },
    }


@router.post("/follow-mode")
def set_follow_mode(payload: FollowModeRequest) -> dict:
    session = require_session()
    try:
        session.control_service.set_follow_mode(payload.follow_mode)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "success": True,
        "message": "follow mode updated",
        "data": {"follow_mode": session.control_service.get_follow_mode()},
    }
