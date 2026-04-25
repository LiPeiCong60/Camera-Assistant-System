"""AI application routes for device_runtime API."""

from __future__ import annotations

import os
import tempfile
from typing import Literal

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field

from device_runtime.api.dependencies import require_session
from device_runtime.api.session_manager import session_manager
from device_runtime.interfaces.ai_assistant import (
    BackgroundAnalysis,
    CaptureAnalysis,
    build_ai_assistant_from_env,
)

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


class ScanRequest(BaseModel):
    pan_range: float = Field(6.0, ge=1.0, le=90.0)
    tilt_range: float = Field(3.0, ge=1.0, le=90.0)
    pan_step: float = Field(4.0, ge=0.8, le=45.0)
    tilt_step: float = Field(3.0, ge=0.8, le=45.0)
    max_candidates: int = Field(5, ge=2, le=9)
    settle_s: float = Field(0.5, ge=0.1, le=10.0)

    def to_scan_config(self) -> dict:
        return {
            "pan_range": float(self.pan_range),
            "tilt_range": float(self.tilt_range),
            "pan_step": float(self.pan_step),
            "tilt_step": float(self.tilt_step),
            "max_candidates": int(self.max_candidates),
            "settle_s": float(self.settle_s),
        }


class BackgroundLockStartRequest(ScanRequest):
    delay_s: float = Field(0.0, ge=0.0, le=30.0)


def _serialize_photo_analysis(analysis: CaptureAnalysis) -> dict:
    return {
        "score": analysis.score,
        "summary": analysis.summary,
        "suggestions": analysis.suggestions,
    }


def _serialize_background_analysis(analysis: BackgroundAnalysis) -> dict:
    return {
        "score": analysis.score,
        "summary": analysis.summary,
        "placement": analysis.placement,
        "camera_angle": analysis.camera_angle,
        "lighting": analysis.lighting,
        "suggestions": analysis.suggestions,
        "recommended_pan_delta": analysis.recommended_pan_delta,
        "recommended_tilt_delta": analysis.recommended_tilt_delta,
        "target_box_norm": list(analysis.target_box_norm),
    }


def _resolve_upload_analysis_context():
    session = session_manager.current_session()
    if session is not None:
        return session.ai_assistant, session.build_ai_context(), True
    return build_ai_assistant_from_env(), {}, False


def _ensure_valid_image(image_path: str) -> None:
    from PIL import Image, UnidentifiedImageError

    try:
        with Image.open(image_path) as image:
            image.verify()
    except (UnidentifiedImageError, OSError) as exc:
        raise ValueError("uploaded file is not a valid image") from exc


@router.post("/analyze-upload")
async def analyze_uploaded_photo(
    file: UploadFile = File(...),
    analysis_type: Literal["photo", "background"] = Form("photo"),
) -> dict:
    suffix = os.path.splitext(file.filename or "")[1] or ".jpg"
    tmp_path = None
    try:
        raw = await file.read()
        if not raw:
            raise ValueError("uploaded image is empty")
        with tempfile.NamedTemporaryFile(prefix="ai_upload_", suffix=suffix, delete=False) as tmp:
            tmp_path = tmp.name
            tmp.write(raw)

        _ensure_valid_image(tmp_path)
        ai_assistant, context, used_session_context = _resolve_upload_analysis_context()
        if analysis_type == "background":
            analysis = ai_assistant.analyze_background(tmp_path, context=context)
            data = _serialize_background_analysis(analysis)
        else:
            analysis = ai_assistant.analyze_capture(tmp_path, context=context)
            data = _serialize_photo_analysis(analysis)

        return {
            "success": True,
            "message": "upload analyzed",
            "data": {
                "filename": file.filename,
                "analysis_type": analysis_type,
                "used_session_context": used_session_context,
                "analysis": data,
            },
        }
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass


@router.post("/angle-search/start")
def start_angle_search(payload: ScanRequest | None = None) -> dict:
    session = require_session()
    payload = payload or ScanRequest()
    try:
        session.start_angle_search_async(payload.to_scan_config())
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "success": True,
        "message": "ai angle search started",
        "data": {
            "ai_angle_search_running": True,
            "scan_config": payload.to_scan_config(),
        },
    }


@router.post("/background-lock/start")
def start_background_lock(payload: BackgroundLockStartRequest | None = None) -> dict:
    session = require_session()
    payload = payload or BackgroundLockStartRequest()
    try:
        session.start_background_lock_async(payload.to_scan_config(), payload.delay_s)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "success": True,
        "message": "background lock scan started",
        "data": {
            "background_lock_running": True,
            "delay_s": payload.delay_s,
            "scan_config": payload.to_scan_config(),
        },
    }


@router.post("/background-lock/unlock")
def unlock_background_lock() -> dict:
    session = require_session()
    try:
        session.ai_orchestrator.unlock_background_lock()
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {
        "success": True,
        "message": "background lock disabled",
        "data": {
            "ai_lock_status": {
                "enabled": session.runtime_state.ai_lock_mode_enabled,
                "fit_score": session.runtime_state.ai_lock_fit_score,
                "target_box_norm": session.runtime_state.ai_lock_target_box_norm,
            },
        },
    }


@router.get("/status")
def get_ai_status() -> dict:
    session = require_session()
    return {
        "success": True,
        "message": "ok",
        "data": session.build_status().get("ai_status", {}),
    }


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
