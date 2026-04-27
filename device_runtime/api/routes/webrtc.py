"""WebRTC signaling routes for mobile camera push and processed preview."""

from __future__ import annotations

import asyncio
import contextlib
import logging
import time
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
_ICE_GATHERING_TIMEOUT_S = 5.0
_webrtc_debug: dict[str, Any] = {
    "offer_count": 0,
    "last_offer_at": None,
    "last_answer_at": None,
    "last_error": None,
    "last_track_kind": None,
    "receiver_started_at": None,
    "receiver_stopped_at": None,
    "frames_received": 0,
    "last_frame_at": None,
    "ice_gathering_state": None,
    "ice_connection_state": None,
    "peer_connection_state": None,
}


def _mark_webrtc_debug(**updates: Any) -> None:
    _webrtc_debug.update(updates)


def get_webrtc_debug_status() -> dict[str, Any]:
    return dict(_webrtc_debug)


def _webrtc_notice(message: str, *args: Any) -> None:
    text = message % args if args else message
    print(f"[device-webrtc] {text}", flush=True)
    _logger.warning(text)


class WebRtcOfferRequest(BaseModel):
    sdp: str = Field(min_length=1)
    type: str = Field(min_length=1)


class DevicePreviewVideoTrack(VideoStreamTrack):
    """aiortc video track backed by the processed device preview frame."""

    def __init__(self, session: DeviceSessionContext, fps: float = 20.0) -> None:
        super().__init__()
        self._session = session
        normalized_fps = min(20.0, max(5.0, float(fps)))
        self._frame_interval_s = 1.0 / normalized_fps
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
    _mark_webrtc_debug(receiver_started_at=time.time(), receiver_stopped_at=None)
    _webrtc_notice("mobile video receiver started")
    try:
        while True:
            frame = await track.recv()
            image = frame.to_ndarray(format="bgr24")
            mobile_push_frame_store.set_frame(image)
            frame_count = int(_webrtc_debug.get("frames_received") or 0) + 1
            _mark_webrtc_debug(frames_received=frame_count, last_frame_at=time.time())
            if frame_count == 1:
                _webrtc_notice(
                    "first mobile video frame received shape=%s",
                    getattr(image, "shape", None),
                )
    except asyncio.CancelledError:
        raise
    except Exception as exc:
        _mark_webrtc_debug(last_error=str(exc))
        _logger.exception("WebRTC mobile video receiver stopped unexpectedly")
    finally:
        _mark_webrtc_debug(receiver_stopped_at=time.time())
        _webrtc_notice("mobile video receiver stopped")


async def _wait_for_ice_gathering(pc: RTCPeerConnection) -> None:
    if pc.iceGatheringState == "complete":
        return
    done = asyncio.Event()

    @pc.on("icegatheringstatechange")
    def on_ice_gathering_state_change() -> None:
        _mark_webrtc_debug(ice_gathering_state=pc.iceGatheringState)
        _webrtc_notice("ICE gathering state=%s", pc.iceGatheringState)
        if pc.iceGatheringState == "complete":
            done.set()

    with contextlib.suppress(asyncio.TimeoutError):
        await asyncio.wait_for(done.wait(), timeout=_ICE_GATHERING_TIMEOUT_S)


@router.post("/offer")
async def accept_webrtc_offer(payload: WebRtcOfferRequest) -> dict:
    _mark_webrtc_debug(
        offer_count=int(_webrtc_debug.get("offer_count") or 0) + 1,
        last_offer_at=time.time(),
        last_answer_at=None,
        last_error=None,
        last_track_kind=None,
        receiver_started_at=None,
        receiver_stopped_at=None,
        frames_received=0,
        last_frame_at=None,
        ice_gathering_state=None,
        ice_connection_state=None,
        peer_connection_state=None,
    )
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
        track_kind = getattr(track, "kind", None)
        _mark_webrtc_debug(last_track_kind=track_kind)
        _webrtc_notice("track received kind=%s", track_kind)
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
        _mark_webrtc_debug(peer_connection_state=pc.connectionState)
        _webrtc_notice("peer connection state=%s", pc.connectionState)
        if pc.connectionState in {"failed", "closed", "disconnected"}:
            for task in list(receiver_tasks):
                task.cancel()
            await pc.close()
            _peer_connections.discard(pc)

    @pc.on("iceconnectionstatechange")
    async def on_iceconnectionstatechange() -> None:
        _mark_webrtc_debug(ice_connection_state=pc.iceConnectionState)
        _webrtc_notice("ICE connection state=%s", pc.iceConnectionState)

    try:
        await pc.setRemoteDescription(
            RTCSessionDescription(sdp=payload.sdp, type=payload.type)
        )
        pc.addTrack(DevicePreviewVideoTrack(session, fps=session.config.app.ui_refresh_fps))
        answer = await pc.createAnswer()
        await pc.setLocalDescription(answer)
        await _wait_for_ice_gathering(pc)
        _mark_webrtc_debug(
            last_answer_at=time.time(),
            ice_gathering_state=pc.iceGatheringState,
        )
    except Exception as exc:
        _mark_webrtc_debug(last_error=str(exc))
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
