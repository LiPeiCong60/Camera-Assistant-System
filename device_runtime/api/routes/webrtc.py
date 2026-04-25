"""WebRTC signaling routes for mobile camera push and processed preview."""

from __future__ import annotations

import asyncio
import contextlib
import logging
from fractions import Fraction
from typing import Any

import cv2
import numpy as np
from aiortc import RTCPeerConnection, RTCSessionDescription, VideoStreamTrack
from av import VideoFrame
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from device_runtime.api.dependencies import require_session
from device_runtime.api.session_manager import DeviceSessionContext
from device_runtime.vision.video_source import MOBILE_PUSH_STREAM_URL, mobile_push_frame_store

router = APIRouter(prefix="/api/device/webrtc", tags=["device-webrtc"])
_logger = logging.getLogger(__name__)
_peer_connections: set[RTCPeerConnection] = set()


class WebRtcOfferRequest(BaseModel):
    sdp: str = Field(min_length=1)
    type: str = Field(min_length=1)


class DevicePreviewVideoTrack(VideoStreamTrack):
    """aiortc video track backed by the processed device preview frame."""

    def __init__(self, session: DeviceSessionContext, fps: float = 20.0) -> None:
        super().__init__()
        self._session = session
        self._frame_interval_s = 1.0 / max(1.0, fps)
        self._next_pts = 0
        self._time_base = Fraction(1, 90000)

    async def recv(self) -> VideoFrame:
        await asyncio.sleep(self._frame_interval_s)
        frame = await asyncio.to_thread(self._read_preview_or_placeholder)
        video_frame = VideoFrame.from_ndarray(frame, format="bgr24")
        self._next_pts += int(90000 * self._frame_interval_s)
        video_frame.pts = self._next_pts
        video_frame.time_base = self._time_base
        return video_frame

    def _read_preview_or_placeholder(self) -> np.ndarray:
        try:
            frame = self._session.get_preview_frame()
            return np.ascontiguousarray(frame)
        except Exception:
            placeholder = np.zeros((480, 640, 3), dtype=np.uint8)
            cv2.putText(
                placeholder,
                "Waiting for mobile video...",
                (42, 245),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (210, 210, 210),
                2,
                cv2.LINE_AA,
            )
            return placeholder


async def _consume_mobile_video(track: Any) -> None:
    while True:
        frame = await track.recv()
        image = frame.to_ndarray(format="bgr24")
        mobile_push_frame_store.set_frame(image)


@router.post("/offer")
async def accept_webrtc_offer(payload: WebRtcOfferRequest) -> dict:
    session = require_session()
    if session.stream_url.strip().lower() != MOBILE_PUSH_STREAM_URL:
        raise HTTPException(
            status_code=409,
            detail="current session stream_url is not mobile_push",
        )

    pc = RTCPeerConnection()
    _peer_connections.add(pc)
    receiver_tasks: set[asyncio.Task[None]] = set()

    @pc.on("track")
    def on_track(track: Any) -> None:
        if track.kind != "video":
            return
        task = asyncio.create_task(_consume_mobile_video(track))
        receiver_tasks.add(task)
        task.add_done_callback(receiver_tasks.discard)

        @track.on("ended")
        async def on_ended() -> None:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task

    @pc.on("connectionstatechange")
    async def on_connectionstatechange() -> None:
        if pc.connectionState in {"failed", "closed", "disconnected"}:
            for task in list(receiver_tasks):
                task.cancel()
            await pc.close()
            _peer_connections.discard(pc)

    try:
        await pc.setRemoteDescription(
            RTCSessionDescription(sdp=payload.sdp, type=payload.type)
        )
        pc.addTrack(DevicePreviewVideoTrack(session, fps=session.config.app.ui_refresh_fps))
        answer = await pc.createAnswer()
        await pc.setLocalDescription(answer)
    except Exception as exc:
        _peer_connections.discard(pc)
        await pc.close()
        _logger.exception("failed to negotiate WebRTC offer")
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {
        "success": True,
        "message": "webrtc answer created",
        "data": {
            "sdp": pc.localDescription.sdp,
            "type": pc.localDescription.type,
        },
    }


async def close_webrtc_peers() -> None:
    peers = list(_peer_connections)
    _peer_connections.clear()
    await asyncio.gather(*(peer.close() for peer in peers), return_exceptions=True)
