"""Control routes for device_runtime API."""

from __future__ import annotations

from typing import Any

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


class SensitivityRequest(BaseModel):
    sensitivity: float


class TrackTargetRequest(BaseModel):
    target_type: str | None = None
    target_x: float | None = None
    target_y: float | None = None
    desired_x: float | None = None
    desired_y: float | None = None
    confidence: float | None = None
    source: str | None = None
    frame: dict[str, Any] | None = None
    timestamp_ms: int | None = None
    target: Any = None
    x: float | None = None
    y: float | None = None


def _clamp01(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def _value_from_target(payload: TrackTargetRequest, *keys: str) -> Any:
    if isinstance(payload.target, dict):
        for key in keys:
            value = payload.target.get(key)
            if value is not None:
                return value
    return None


def _track_target_type(payload: TrackTargetRequest) -> str:
    if payload.target_type is not None:
        return payload.target_type
    from_target = _value_from_target(payload, "target_type", "type", "target")
    if from_target is not None:
        return str(from_target)
    if isinstance(payload.target, str):
        return payload.target
    return "shoulder_center"


def _track_coordinate(payload: TrackTargetRequest, canonical: str, legacy: str) -> float:
    value = getattr(payload, canonical)
    if value is None:
        value = getattr(payload, legacy)
    if value is None:
        value = _value_from_target(payload, canonical, legacy)
    if value is None:
        raise ValueError(f"{canonical} is required")
    return _clamp01(float(value))


def _optional_track_coordinate(
    payload: TrackTargetRequest,
    canonical: str,
    legacy: str,
    default: float,
) -> float:
    value = getattr(payload, canonical)
    if value is None:
        value = _value_from_target(payload, canonical, legacy)
    if value is None:
        return _clamp01(default)
    return _clamp01(float(value))


@router.post("/manual-move")
def manual_move(payload: ManualMoveRequest) -> dict:
    session = require_session()
    sensitivity = session.control_service.get_sensitivity()
    try:
        if payload.pan_delta is not None or payload.tilt_delta is not None:
            session.control_service.move_relative(
                float(payload.pan_delta or 0.0) * sensitivity,
                float(payload.tilt_delta or 0.0) * sensitivity,
                smooth=False,
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
        "data": {
            "follow_mode": session.control_service.get_follow_mode(),
            "target_type": session.control_service.get_follow_target_type(),
        },
    }


@router.post("/sensitivity")
def set_sensitivity(payload: SensitivityRequest) -> dict:
    session = require_session()
    try:
        session.control_service.set_sensitivity(payload.sensitivity)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "success": True,
        "message": "sensitivity updated",
        "data": {"sensitivity": session.control_service.get_sensitivity()},
    }


@router.post("/track-target")
def track_target(payload: TrackTargetRequest) -> dict:
    session = require_session()
    try:
        target_x = _track_coordinate(payload, "target_x", "x")
        target_y = _track_coordinate(payload, "target_y", "y")
        desired_x = _optional_track_coordinate(payload, "desired_x", "anchor_x", 0.5)
        desired_y = _optional_track_coordinate(payload, "desired_y", "anchor_y", 0.5)
        confidence = _clamp01(payload.confidence if payload.confidence is not None else 1.0)
        command = session.control_service.track_target(
            target_x,
            target_y,
            desired_x=desired_x,
            desired_y=desired_y,
            target_type=_track_target_type(payload),
            confidence=confidence,
            frame=payload.frame,
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    pan, tilt = session.control_service.get_current_angles(prefer_feedback=True)
    return {
        "success": True,
        "message": "track target accepted",
        "data": {
            "target_type": session.control_service.get_follow_target_type(),
            "target_x": target_x,
            "target_y": target_y,
            "desired_x": desired_x,
            "desired_y": desired_y,
            "confidence": confidence,
            "source": payload.source,
            "timestamp_ms": payload.timestamp_ms,
            "applied": command is not None,
            "pan_delta": round(float(command.pan_delta), 3) if command is not None else 0.0,
            "tilt_delta": round(float(command.tilt_delta), 3) if command is not None else 0.0,
            "current_pan": round(float(pan), 3),
            "current_tilt": round(float(tilt), 3),
        },
    }
