"""Status routes for device_runtime API."""

from __future__ import annotations

import asyncio

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import Response
from pydantic import BaseModel

from device_runtime.api.dependencies import require_session
from device_runtime.api.session_manager import session_manager

router = APIRouter(tags=["device-status"])

PREVIEW_WS_INTERVAL_S = 1.0 / 20.0


class OverlayConfigRequest(BaseModel):
    enabled: bool | None = None
    show_live_person_bbox: bool | None = None
    show_live_body_skeleton: bool | None = None
    show_live_hands: bool | None = None
    show_template_bbox: bool | None = None
    show_template_skeleton: bool | None = None
    show_ai_lock_box: bool | None = None


class GestureConfigRequest(BaseModel):
    capture_enabled: bool | None = None
    force_ok_enabled: bool | None = None
    auto_analyze_enabled: bool | None = None


class DeviceRuntimeConfigRequest(BaseModel):
    overlay: OverlayConfigRequest | None = None
    gesture: GestureConfigRequest | None = None


def _model_payload(model: BaseModel | None) -> dict:
    if model is None:
        return {}
    if hasattr(model, "model_dump"):
        return model.model_dump(exclude_none=True)
    return model.dict(exclude_none=True)


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


@router.patch("/api/device/config")
def update_runtime_config(payload: DeviceRuntimeConfigRequest) -> dict:
    session = require_session()
    status = session.update_runtime_options(
        overlay=_model_payload(payload.overlay) if payload.overlay is not None else None,
        gesture=_model_payload(payload.gesture) if payload.gesture is not None else None,
    )
    return {
        "success": True,
        "message": "config updated",
        "data": status,
    }


@router.get("/api/device/preview.jpg")
def get_preview_frame() -> Response:
    session = require_session()
    try:
        jpeg_bytes = session.get_preview_jpeg_bytes()
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return Response(
        content=jpeg_bytes,
        media_type="image/jpeg",
        headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
    )


@router.websocket("/api/device/preview-ws")
async def preview_stream(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        session = require_session()
    except HTTPException as exc:
        await websocket.close(code=1008, reason=str(exc.detail))
        return

    try:
        while True:
            if session_manager.current_session() is not session:
                await websocket.close(code=1012, reason="device session changed")
                return
            try:
                jpeg_bytes = await asyncio.to_thread(
                    session.get_preview_jpeg_bytes,
                    quality=65,
                )
            except ValueError:
                await asyncio.sleep(PREVIEW_WS_INTERVAL_S)
                continue
            await websocket.send_bytes(jpeg_bytes)
            await asyncio.sleep(PREVIEW_WS_INTERVAL_S)
    except WebSocketDisconnect:
        return
