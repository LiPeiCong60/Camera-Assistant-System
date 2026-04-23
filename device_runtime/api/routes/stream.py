"""Stream routes for device_runtime API."""

from __future__ import annotations

import json

import cv2
import numpy as np
from fastapi import APIRouter, File, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field

from device_runtime.api.dependencies import require_session
from device_runtime.vision.video_source import MOBILE_PUSH_STREAM_URL, mobile_push_frame_store

router = APIRouter(prefix="/api/device/stream", tags=["device-stream"])

SUPPORTED_MOBILE_WS_FORMATS = {"nv21"}
SUPPORTED_MOBILE_ROTATIONS = {0, 90, 180, 270}


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


@router.websocket("/mobile-ws")
async def push_mobile_stream(websocket: WebSocket) -> None:
    await websocket.accept()

    try:
        session = require_session()
    except HTTPException as exc:
        await websocket.close(code=1008, reason=str(exc.detail))
        return

    if session.stream_url.strip().lower() != MOBILE_PUSH_STREAM_URL:
        await websocket.close(
            code=1008,
            reason="current session stream_url is not mobile_push",
        )
        return

    try:
        raw_config = await websocket.receive_text()
        config = json.loads(raw_config)
        width = int(config.get("width", 0))
        height = int(config.get("height", 0))
        frame_format = str(config.get("format", "")).lower()
        rotation_degrees = int(config.get("rotation_degrees", 0)) % 360
        if (
            config.get("type") != "config"
            or frame_format not in SUPPORTED_MOBILE_WS_FORMATS
            or rotation_degrees not in SUPPORTED_MOBILE_ROTATIONS
            or width <= 0
            or height <= 0
        ):
            await websocket.close(code=1003, reason="invalid mobile stream config")
            return

        expected_size = width * height * 3 // 2
        while True:
            payload = await websocket.receive_bytes()
            if len(payload) != expected_size:
                await websocket.send_json(
                    {
                        "type": "error",
                        "message": "invalid frame payload size",
                        "expected_size": expected_size,
                        "actual_size": len(payload),
                    }
                )
                continue

            yuv = np.frombuffer(payload, dtype=np.uint8).reshape(
                (height * 3 // 2, width)
            )
            frame = cv2.cvtColor(yuv, cv2.COLOR_YUV2BGR_NV21)
            if rotation_degrees == 90:
                frame = cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
            elif rotation_degrees == 180:
                frame = cv2.rotate(frame, cv2.ROTATE_180)
            elif rotation_degrees == 270:
                frame = cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
            mobile_push_frame_store.set_frame(frame)
    except (json.JSONDecodeError, ValueError):
        await websocket.close(code=1003, reason="invalid mobile stream config")
    except WebSocketDisconnect:
        return


@router.post("/frame")
async def push_frame(file: UploadFile = File(...)) -> dict:
    session = require_session()
    if session.stream_url.strip().lower() != MOBILE_PUSH_STREAM_URL:
        raise HTTPException(
            status_code=409,
            detail="current session stream_url is not mobile_push",
        )

    payload = await file.read()
    if not payload:
        raise HTTPException(status_code=400, detail="empty frame payload")

    encoded = np.frombuffer(payload, dtype=np.uint8)
    frame = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
    if frame is None:
        raise HTTPException(status_code=400, detail="invalid jpeg frame")

    mobile_push_frame_store.set_frame(frame)
    return {
        "success": True,
        "message": "mobile frame accepted",
        "data": {
            "stream_url": session.stream_url,
            "width": int(frame.shape[1]),
            "height": int(frame.shape[0]),
        },
    }
