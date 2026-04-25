"""Minimal realtime session manager for device runtime local API."""

from __future__ import annotations

import logging
import os
import sys
import threading
import time
from dataclasses import dataclass
from typing import Any

import cv2

from device_runtime.app_core import build_draw_vision
from device_runtime.config import GimbalConfig, default_config
from device_runtime.control.gimbal_controller import (
    GimbalController,
    MockServoDriver,
    ServoDriver,
    TTLBusSerialDriver,
)
from device_runtime.control.tracking_controller import TrackingController
from device_runtime.interfaces.ai_assistant import (
    build_ai_assistant_from_env,
    describe_ai_assistant,
)
from device_runtime.interfaces.capture_trigger import LocalFileCaptureTrigger
from device_runtime.interfaces.target_strategy import TargetPreset, build_target_strategy
from device_runtime.services.ai_orchestrator import AIOrchestrator
from device_runtime.services.capture_service import CaptureResult, CaptureService
from device_runtime.mode_manager import ControlMode, ModeManager
from device_runtime.services.control_service import ControlService
from device_runtime.services.frame_processor import FrameProcessor
from device_runtime.services.runtime_state import RuntimeState
from device_runtime.services.template_service import TemplateService
from device_runtime.repositories.local_template_repository import LocalTemplateRepository
from device_runtime.templates.template_compose import TemplateLibrary, TemplateProfile
from device_runtime.templates.template_compose import GestureCaptureState
from device_runtime.utils.common_types import BBox, DetectionResult, LineSegment, Point, VisionResult
from device_runtime.utils.overlay_renderer import DeviceOverlayRenderer, OverlaySettings
from device_runtime.vision.detector import AsyncDetector, build_runtime_detector
from device_runtime.vision.video_source import build_video_source


@dataclass(slots=True)
class SessionOpenPayload:
    session_code: str
    stream_url: str
    mirror_view: bool = True
    start_mode: str = "MANUAL"


@dataclass(slots=True)
class GestureSettings:
    capture_enabled: bool = False
    force_ok_enabled: bool = False
    auto_analyze_enabled: bool = False

    def as_dict(self) -> dict[str, bool]:
        return {
            "capture_enabled": self.capture_enabled,
            "force_ok_enabled": self.force_ok_enabled,
            "auto_analyze_enabled": self.auto_analyze_enabled,
        }

    def update_from_dict(self, values: dict[str, object]) -> None:
        for key in self.as_dict():
            if key in values and values[key] is not None:
                setattr(self, key, bool(values[key]))


def _env_text(name: str) -> str | None:
    value = os.getenv(name)
    if value is None:
        return None
    normalized = value.strip()
    return normalized or None


def _env_int(name: str, default: int) -> int:
    value = _env_text(name)
    if value is None:
        return default
    return int(value)


def _env_float(name: str, default: float) -> float:
    value = _env_text(name)
    if value is None:
        return default
    return float(value)


def _resolve_driver_kind() -> str:
    configured = _env_text("DEVICE_SERVO_DRIVER")
    if configured is not None:
        return configured.lower()
    return "mock" if sys.platform.startswith("win") else "ttl_bus"


def _apply_gimbal_env_overrides(config: GimbalConfig) -> None:
    config.driver_kind = _resolve_driver_kind()
    config.ttl_bus.port = _env_text("DEVICE_TTL_SERIAL_PORT") or config.ttl_bus.port
    config.ttl_bus.baudrate = _env_int("DEVICE_TTL_BAUDRATE", config.ttl_bus.baudrate)
    config.ttl_bus.move_time_ms = _env_int(
        "DEVICE_TTL_MOVE_TIME_MS",
        config.ttl_bus.move_time_ms,
    )
    config.ttl_bus.timeout_s = _env_float(
        "DEVICE_TTL_TIMEOUT_S",
        config.ttl_bus.timeout_s,
    )

    config.pan.servo_id = _env_int("DEVICE_PAN_SERVO_ID", config.pan.servo_id)
    config.tilt.servo_id = _env_int("DEVICE_TILT_SERVO_ID", config.tilt.servo_id)
    config.pan.min_angle = _env_float("DEVICE_PAN_MIN_ANGLE", config.pan.min_angle)
    config.pan.max_angle = _env_float("DEVICE_PAN_MAX_ANGLE", config.pan.max_angle)
    config.pan.home_angle = _env_float("DEVICE_PAN_HOME_ANGLE", config.pan.home_angle)
    config.pan.max_step_deg = _env_float("DEVICE_PAN_MAX_STEP_DEG", config.pan.max_step_deg)
    config.tilt.min_angle = _env_float("DEVICE_TILT_MIN_ANGLE", config.tilt.min_angle)
    config.tilt.max_angle = _env_float("DEVICE_TILT_MAX_ANGLE", config.tilt.max_angle)
    config.tilt.home_angle = _env_float("DEVICE_TILT_HOME_ANGLE", config.tilt.home_angle)
    config.tilt.max_step_deg = _env_float("DEVICE_TILT_MAX_STEP_DEG", config.tilt.max_step_deg)


def _build_servo_driver(config: GimbalConfig) -> ServoDriver:
    driver_kind = config.driver_kind.lower()
    if driver_kind == "mock":
        return MockServoDriver()
    if driver_kind == "ttl_bus":
        return TTLBusSerialDriver(
            port=config.ttl_bus.port,
            baudrate=config.ttl_bus.baudrate,
            move_time_ms=config.ttl_bus.move_time_ms,
            timeout_s=config.ttl_bus.timeout_s,
        )
    raise RuntimeError(
        "Unsupported DEVICE_SERVO_DRIVER. Expected `mock` or `ttl_bus`."
    )


class DeviceSessionContext:
    """Realtime device session context used by local API endpoints."""

    def __init__(
        self,
        payload: SessionOpenPayload,
        *,
        template_library: TemplateLibrary | None = None,
        template_repository: LocalTemplateRepository | None = None,
        initial_selected_template_id: str | None = None,
    ) -> None:
        self._logger = logging.getLogger(self.__class__.__name__)
        self.session_code = payload.session_code
        self.stream_url = payload.stream_url
        self.mirror_view = bool(payload.mirror_view)
        self.opened_at = time.time()

        self.config = default_config(payload.stream_url)
        _apply_gimbal_env_overrides(self.config.gimbal)
        self.runtime_state = RuntimeState()
        self.mode_manager = ModeManager(initial_mode=ControlMode(payload.start_mode))
        self.tracking = TrackingController(
            self.config.tracking,
            build_target_strategy(TargetPreset.CENTER),
        )
        self.gimbal = GimbalController(self.config.gimbal, _build_servo_driver(self.config.gimbal))
        self.control_service = ControlService(
            mode_manager=self.mode_manager,
            tracking=self.tracking,
            gimbal=self.gimbal,
            runtime_state=self.runtime_state,
            manual_step_deg=self.config.app.manual_step_deg,
        )
        self._logger.info(
            "device_runtime servo driver=%s pan_servo_id=%s tilt_servo_id=%s ttl_port=%s",
            self.config.gimbal.driver_kind,
            self.config.gimbal.pan.servo_id,
            self.config.gimbal.tilt.servo_id,
            self.config.gimbal.ttl_bus.port if self.config.gimbal.driver_kind == "ttl_bus" else "n/a",
        )
        self.template_library = template_library or TemplateLibrary()
        self.template_repository = template_repository or LocalTemplateRepository(
            self.template_library
        )
        self.template_service = TemplateService(
            repository=self.template_repository,
            runtime_state=self.runtime_state,
        )
        self._selected_template_profile: TemplateProfile | None = None
        self._initial_selected_template_id = initial_selected_template_id
        self.capture_trigger = LocalFileCaptureTrigger()
        self.ai_assistant = build_ai_assistant_from_env()
        self.capture_service = CaptureService(
            capture_trigger=self.capture_trigger,
            ai_assistant=self.ai_assistant,
            runtime_state=self.runtime_state,
        )
        self.ai_orchestrator = AIOrchestrator(
            ai_assistant=self.ai_assistant,
            control_service=self.control_service,
            capture_service=self.capture_service,
            runtime_state=self.runtime_state,
            frame_provider=self._read_frame_for_ai,
            capture_frame_for_save=self._capture_frame_for_save,
        )

        self.source = build_video_source(self.config.video)
        self._async_detector: AsyncDetector | None = None
        self._frame_processor: FrameProcessor | None = None
        self._overlay_renderer = DeviceOverlayRenderer()
        self._overlay_settings = OverlaySettings(
            enabled=self.config.app.enable_overlay,
            show_live_body_skeleton=self.config.app.show_body_skeleton,
        )
        self._gesture_settings = GestureSettings()
        self._gesture_state = GestureCaptureState()
        self._last_hands_detected = False
        self._last_hand_count = 0
        self._last_gesture_event: str | None = None
        self._last_gesture_event_at: float | None = None
        self._last_gesture_capture_result: dict[str, Any] | None = None
        self._last_gesture_capture_error: str | None = None
        self._detector_interval_s = 1.0 / max(1.0, self.config.detection.detector_fps)
        self._last_submit_ts = 0.0
        self._stop_event = threading.Event()
        self._frame_thread: threading.Thread | None = None
        self._lock = threading.RLock()
        self._job_lock = threading.RLock()
        self._angle_job: threading.Thread | None = None
        self._background_job: threading.Thread | None = None
        self.last_angle_search_result: dict[str, Any] | None = None
        self.last_angle_search_error: str | None = None
        self.last_background_lock_result: dict[str, Any] | None = None
        self.last_background_lock_error: str | None = None
        self.device_status = "idle"

        if self._initial_selected_template_id:
            try:
                self.select_template(self._initial_selected_template_id)
            except ValueError:
                self._initial_selected_template_id = None

    def start(self) -> None:
        with self._lock:
            self.source.start()
            self._ensure_detector_pipeline()
            self.runtime_state.loop_running = True
            self.device_status = "online"
            self._stop_event.clear()
            self._frame_thread = threading.Thread(
                target=self._frame_loop,
                name=f"device-runtime-{self.session_code}",
                daemon=True,
            )
            self._frame_thread.start()

    def restart_stream(self, stream_url: str) -> None:
        with self._lock:
            self._stop_event.set()
            self.runtime_state.loop_running = False
            self.device_status = "switching_stream"
        if self._frame_thread is not None:
            self._frame_thread.join(timeout=2.0)
            self._frame_thread = None
        self.source.stop()

        self.stream_url = stream_url
        self.config = default_config(stream_url)
        self.source = build_video_source(self.config.video)
        self._detector_interval_s = 1.0 / max(1.0, self.config.detection.detector_fps)
        self._last_submit_ts = 0.0
        self.runtime_state.last_runtime_error = None
        self.runtime_state.last_frame_at = None
        self.runtime_state.last_detection_at = None
        self.runtime_state.latest_frame = None
        self.runtime_state.latest_vision = None
        self.runtime_state.stable_detection = None

        with self._lock:
            self.source.start()
            self.runtime_state.loop_running = True
            self.device_status = "online"
            self._stop_event.clear()
            self._frame_thread = threading.Thread(
                target=self._frame_loop,
                name=f"device-runtime-{self.session_code}",
                daemon=True,
            )
            self._frame_thread.start()

    def close(self) -> None:
        with self._lock:
            self._stop_event.set()
            self.runtime_state.loop_running = False
            self.device_status = "offline"
        if self._frame_thread is not None:
            self._frame_thread.join(timeout=2.0)
            self._frame_thread = None
        if self._async_detector is not None:
            self._async_detector.close()
            self._async_detector = None
        self.source.stop()
        for worker in (self._angle_job, self._background_job):
            if worker is not None and worker.is_alive():
                worker.join(timeout=2.0)
        self.gimbal.close()

    def build_ai_context(self) -> dict[str, Any]:
        compose_feedback = self.runtime_state.last_compose_feedback
        return {
            "session_code": self.session_code,
            "stream_url": self.stream_url,
            "mode": self.control_service.get_mode().value,
            "follow_mode": self.runtime_state.follow_mode,
            "speed_mode": self.runtime_state.speed_mode,
            "compose_score": getattr(compose_feedback, "total_score", None),
            "template_id": self.runtime_state.selected_template_id,
            "mirror_view": self.mirror_view,
        }

    def build_status(self) -> dict:
        current_pan, current_tilt = self.control_service.get_current_angles(prefer_feedback=True)
        stable = self.runtime_state.stable_detection
        compose_feedback = self.runtime_state.last_compose_feedback
        if self.runtime_state.selected_template_id is None:
            compose_feedback = None
        stable_bbox = None
        if stable is not None:
            stable_bbox = {
                "x": stable.bbox.x,
                "y": stable.bbox.y,
                "w": stable.bbox.w,
                "h": stable.bbox.h,
                "confidence": stable.confidence,
                "label": stable.label,
            }
        ai_provider_status = describe_ai_assistant(self.ai_assistant)
        latest_capture_analysis = self.runtime_state.latest_capture_analysis
        latest_capture = {
            "path": self.runtime_state.latest_capture_path,
            "analysis": {
                "score": getattr(latest_capture_analysis, "score", None),
                "summary": getattr(latest_capture_analysis, "summary", None),
                "suggestions": list(getattr(latest_capture_analysis, "suggestions", []) or []),
            }
            if latest_capture_analysis is not None
            else None,
            "analysis_error": self.runtime_state.latest_capture_error,
        }

        return {
            "session_opened": True,
            "session_code": self.session_code,
            "stream_url": self.stream_url,
            "mirror_view": self.mirror_view,
            "mode": self.control_service.get_mode().value,
            "follow_mode": self.runtime_state.follow_mode,
            "speed_mode": self.runtime_state.speed_mode,
            "device_status": self.device_status,
            "loop_running": self.runtime_state.loop_running,
            "detector_backend": self.runtime_state.detector_backend,
            "last_runtime_error": self.runtime_state.last_runtime_error,
            "last_frame_at": self.runtime_state.last_frame_at,
            "last_detection_at": self.runtime_state.last_detection_at,
            "ai_provider_status": ai_provider_status,
            "latest_capture": latest_capture,
            "current_pan": round(float(current_pan), 3),
            "current_tilt": round(float(current_tilt), 3),
            "selected_template_id": self.runtime_state.selected_template_id,
            "template_status": {
                "selected": self.runtime_state.selected_template_id is not None,
                "template_name": self.runtime_state.selected_template_name,
                "last_updated_at": self.runtime_state.selected_template_updated_at,
                "compose_score": getattr(compose_feedback, "total_score", None),
                "ready": getattr(compose_feedback, "ready", False),
                "messages": list(getattr(compose_feedback, "messages", []) or []),
            },
            "tracking_status": {
                "stable_detection": self.runtime_state.stable_detection is not None,
                "reliable_detection_streak": self.runtime_state.reliable_detection_streak,
                "stable_bbox": stable_bbox,
            },
            "ai_lock_status": {
                "enabled": self.runtime_state.ai_lock_mode_enabled,
                "fit_score": self.runtime_state.ai_lock_fit_score,
                "target_box_norm": self.runtime_state.ai_lock_target_box_norm,
            },
            "ai_angle_search_running": self.runtime_state.ai_angle_search_running,
            "background_lock_running": self._background_job is not None and self._background_job.is_alive(),
            "last_angle_search_result": self.last_angle_search_result,
            "last_angle_search_error": self.last_angle_search_error,
            "last_background_lock_result": self.last_background_lock_result,
            "last_background_lock_error": self.last_background_lock_error,
            "ai_status": {
                "angle_search_running": self.runtime_state.ai_angle_search_running,
                "background_lock_running": self._background_job is not None and self._background_job.is_alive(),
                "lock_enabled": self.runtime_state.ai_lock_mode_enabled,
                "lock_fit_score": self.runtime_state.ai_lock_fit_score,
                "lock_target_box_norm": self.runtime_state.ai_lock_target_box_norm,
                "last_angle_search_result": self.last_angle_search_result,
                "last_angle_search_error": self.last_angle_search_error,
                "last_background_lock_result": self.last_background_lock_result,
                "last_background_lock_error": self.last_background_lock_error,
                "provider_status": ai_provider_status,
                "latest_capture": latest_capture,
            },
            "overlay_status": self._overlay_settings.as_dict(),
            "gesture_status": {
                **self._gesture_settings.as_dict(),
                "open_fist_requires_compose_ready": True,
                "hands_detected": self._last_hands_detected,
                "hand_count": self._last_hand_count,
                "last_event": self._last_gesture_event,
                "last_event_at": self._last_gesture_event_at,
                "last_capture_result": self._last_gesture_capture_result,
                "last_capture_error": self._last_gesture_capture_error,
                "state": self._gesture_state.snapshot(),
            },
        }

    def update_runtime_options(
        self,
        *,
        overlay: dict[str, object] | None = None,
        gesture: dict[str, object] | None = None,
    ) -> dict:
        with self._lock:
            if overlay is not None:
                self._overlay_settings.update_from_dict(overlay)
            if gesture is not None:
                self._gesture_settings.update_from_dict(gesture)
                if not self._gesture_settings.capture_enabled:
                    self._gesture_state.reset_pose_capture()
                if not self._gesture_settings.force_ok_enabled:
                    self._gesture_state.reset()
            return self.build_status()

    def _ensure_detector_pipeline(self) -> None:
        if self._async_detector is not None and self._frame_processor is not None:
            return
        detector, backend = build_runtime_detector(self.config.detection)
        self.runtime_state.detector_backend = backend
        self.runtime_state.last_runtime_error = None
        self._async_detector = AsyncDetector(detector, skip_frames=self.config.detection.async_skip_frames)
        self._frame_processor = FrameProcessor(
            mode_manager=self.mode_manager,
            tracking=self.tracking,
            runtime_state=self.runtime_state,
        )

    def _frame_loop(self) -> None:
        while not self._stop_event.is_set():
            frame = self.source.read()
            now = time.time()
            if frame is None:
                time.sleep(0.02)
                continue

            self.runtime_state.latest_frame = frame.copy()
            self.runtime_state.last_frame_at = now

            if self._async_detector is None or self._frame_processor is None:
                time.sleep(0.01)
                continue

            if now - self._last_submit_ts >= self._detector_interval_s:
                self._async_detector.submit(frame)
                self._last_submit_ts = now

            _, vision = self._async_detector.latest()
            if self._async_detector.last_error is not None:
                self.runtime_state.last_runtime_error = str(self._async_detector.last_error)
                time.sleep(0.01)
                continue
            self.runtime_state.last_runtime_error = None

            selected_template = self._selected_template_profile
            if selected_template is None:
                selected_template = self.template_service.get_selected_template()

            processed = self._frame_processor.process_frame(
                frame,
                vision,
                selected_template=selected_template,
                mirror_view=self.mirror_view,
                compose_auto_control=True,
                ai_lock_mode_enabled=self.runtime_state.ai_lock_mode_enabled,
                now=now,
            )
            if processed.stable_detection is not None:
                self.runtime_state.last_detection_at = now
                self._update_ai_lock_fit_score(processed.stable_detection, frame.shape)

            self._update_gesture_state(processed, vision, now)

            if processed.tracking_command is not None:
                try:
                    self.gimbal.move_relative(
                        processed.tracking_command.pan_delta,
                        processed.tracking_command.tilt_delta,
                        smooth=True,
                    )
                except Exception as exc:
                    self.runtime_state.last_runtime_error = str(exc)

            time.sleep(0.01)

    def start_angle_search_async(self, scan_config: dict[str, Any]) -> None:
        with self._job_lock:
            if self.ai_orchestrator.angle_search_running:
                raise RuntimeError("AI angle search is already running")
            self.last_angle_search_result = None
            self.last_angle_search_error = None
            self._angle_job = threading.Thread(
                target=self._run_angle_search_job,
                args=(scan_config,),
                name=f"angle-search-{self.session_code}",
                daemon=True,
            )
            self._angle_job.start()

    def start_background_lock_async(self, scan_config: dict[str, Any], delay_s: float) -> None:
        with self._job_lock:
            if self._background_job is not None and self._background_job.is_alive():
                raise RuntimeError("Background lock scan is already running")
            self.last_background_lock_result = None
            self.last_background_lock_error = None
            self._background_job = threading.Thread(
                target=self._run_background_lock_job,
                args=(scan_config, delay_s),
                name=f"background-lock-{self.session_code}",
                daemon=True,
            )
            self._background_job.start()

    def _run_angle_search_job(self, scan_config: dict[str, Any]) -> None:
        try:
            self.last_angle_search_result = self.ai_orchestrator.start_angle_search(scan_config)
        except Exception as exc:
            self.last_angle_search_error = str(exc)

    def _run_background_lock_job(self, scan_config: dict[str, Any], delay_s: float) -> None:
        try:
            self.last_background_lock_result = self.ai_orchestrator.start_background_lock(
                scan_config,
                delay_s=delay_s,
            )
        except Exception as exc:
            self.last_background_lock_error = str(exc)

    def apply_ai_lock(
        self,
        *,
        recommended_pan_delta: float,
        recommended_tilt_delta: float,
        target_box_norm: Any,
    ) -> tuple[float, float]:
        pan_delta = max(-12.0, min(12.0, float(recommended_pan_delta)))
        tilt_delta = max(-12.0, min(12.0, float(recommended_tilt_delta)))
        normalized_box = self._normalize_bbox_norm(target_box_norm)
        if normalized_box[2] <= 0.0 or normalized_box[3] <= 0.0:
            normalized_box = (0.38, 0.18, 0.24, 0.66)

        self.control_service.move_relative(pan_delta, tilt_delta)
        self.runtime_state.ai_lock_target_box_norm = normalized_box
        self.runtime_state.ai_lock_mode_enabled = True
        self.runtime_state.ai_lock_fit_score = 0.0
        return self.control_service.get_current_angles(prefer_feedback=True)

    def trigger_capture(self, *, reason: str, auto_analyze: bool = False) -> CaptureResult:
        frame = self.runtime_state.latest_frame
        if frame is None:
            frame = self._acquire_frame_for_capture()
        if frame is None:
            raise ValueError("no frame available for capture")
        return self.capture_service.capture(
            frame=self._capture_frame_for_save(frame),
            metadata={"reason": reason, "session_code": self.session_code},
            suffix=reason,
            auto_analyze=auto_analyze,
            context=self.build_ai_context(),
        )

    def get_preview_jpeg_bytes(self, *, quality: int = 75) -> bytes:
        frame = self.runtime_state.latest_frame
        if frame is None:
            frame = self._acquire_frame_for_capture()
        if frame is None:
            raise ValueError("no frame available for preview")
        frame = self._build_preview_frame(frame)

        normalized_quality = max(35, min(95, int(quality)))
        success, encoded = cv2.imencode(
            ".jpg",
            frame,
            [int(cv2.IMWRITE_JPEG_QUALITY), normalized_quality],
        )
        if not success:
            raise ValueError("failed to encode preview frame")
        return encoded.tobytes()

    def _build_preview_frame(self, frame):
        preview = frame.copy()
        vision = self.runtime_state.latest_vision
        stable = self.runtime_state.stable_detection
        draw_vision = build_draw_vision(vision, stable) if vision is not None else None
        selected_template = self._selected_template_profile
        if selected_template is None:
            selected_template = self.template_service.get_selected_template()

        if self.mirror_view:
            preview = cv2.flip(preview, 1)
            if draw_vision is not None:
                draw_vision = self._mirror_vision(draw_vision, preview.shape)

        self._overlay_renderer.draw(
            preview,
            vision=draw_vision,
            selected_template=selected_template,
            settings=self._overlay_settings,
            ai_lock_target_box_norm=self.runtime_state.ai_lock_target_box_norm
            if self.runtime_state.ai_lock_mode_enabled
            else None,
        )
        return preview

    def _update_gesture_state(self, processed, vision: VisionResult, now: float) -> None:
        hands = vision.hand_landmarks or []
        self._last_hand_count = len(hands)
        self._last_hands_detected = any(len(hand) >= 21 for hand in hands)

        if not self._gesture_settings.capture_enabled and not self._gesture_settings.force_ok_enabled:
            self._gesture_state.reset()
            return

        selected_template = self._selected_template_profile
        if selected_template is None:
            selected_template = self.template_service.get_selected_template()
        ready_for_pose_capture = (
            self._gesture_settings.capture_enabled
            and self.mode_manager.mode == ControlMode.SMART_COMPOSE
            and selected_template is not None
            and processed.ready_for_gesture
        )
        gesture_event = self._gesture_state.update(
            hands,
            now,
            ready_for_pose_capture=ready_for_pose_capture,
            force_ok_enabled=self._gesture_settings.force_ok_enabled,
        )
        if gesture_event is None:
            return

        self._last_gesture_event = gesture_event
        self._last_gesture_event_at = now
        reason = "gesture_ok" if gesture_event == "force_capture" else "gesture_open_fist"
        try:
            result = self.trigger_capture(
                reason=reason,
                auto_analyze=self._gesture_settings.auto_analyze_enabled,
            )
            self._last_gesture_capture_result = {
                "path": result.path,
                "reason": reason,
                "analysis": {
                    "score": getattr(result.analysis, "score", None),
                    "summary": getattr(result.analysis, "summary", None),
                    "suggestions": list(getattr(result.analysis, "suggestions", []) or []),
                }
                if result.analysis is not None
                else None,
                "analysis_error": result.analysis_error,
            }
            self._last_gesture_capture_error = None
        except Exception as exc:
            self._last_gesture_capture_error = str(exc)
            self._last_gesture_capture_result = None

    @staticmethod
    def _mirror_vision(vision: VisionResult, frame_shape: tuple[int, int, int]) -> VisionResult:
        width = int(frame_shape[1])
        return VisionResult(
            tracking_detection=DeviceSessionContext._mirror_detection(vision.tracking_detection, width),
            tracking_candidates=[
                DeviceSessionContext._mirror_detection(candidate, width)
                for candidate in (vision.tracking_candidates or [])
            ],
            face_tracking_detection=DeviceSessionContext._mirror_detection(
                vision.face_tracking_detection,
                width,
            ),
            person_bbox=DeviceSessionContext._mirror_bbox(vision.person_bbox, width),
            face_bbox=DeviceSessionContext._mirror_bbox(vision.face_bbox, width),
            body_skeleton=[
                DeviceSessionContext._mirror_segment(seg, width)
                for seg in (vision.body_skeleton or [])
            ],
            face_mesh=[
                DeviceSessionContext._mirror_segment(seg, width)
                for seg in (vision.face_mesh or [])
            ],
            hand_landmarks=[
                [DeviceSessionContext._mirror_point(point, width) for point in hand]
                for hand in (vision.hand_landmarks or [])
            ],
            hand_handedness=vision.hand_handedness,
        )

    @staticmethod
    def _mirror_detection(detection: DetectionResult | None, width: int) -> DetectionResult | None:
        if detection is None:
            return None
        return DetectionResult(
            bbox=DeviceSessionContext._mirror_bbox(detection.bbox, width),
            confidence=detection.confidence,
            label=detection.label,
            track_id=detection.track_id,
            anchor_point=DeviceSessionContext._mirror_point(detection.anchor_point, width)
            if detection.anchor_point is not None
            else None,
            pose_landmarks={
                key: DeviceSessionContext._mirror_point(point, width)
                for key, point in (detection.pose_landmarks or {}).items()
            },
        )

    @staticmethod
    def _mirror_bbox(bbox: BBox | None, width: int) -> BBox | None:
        if bbox is None:
            return None
        return BBox(x=max(0, width - bbox.x - bbox.w), y=bbox.y, w=bbox.w, h=bbox.h)

    @staticmethod
    def _mirror_point(point: Point, width: int) -> Point:
        return Point(x=float(width - 1) - float(point.x), y=float(point.y))

    @staticmethod
    def _mirror_segment(segment: LineSegment, width: int) -> LineSegment:
        return LineSegment(
            start=DeviceSessionContext._mirror_point(segment.start, width),
            end=DeviceSessionContext._mirror_point(segment.end, width),
        )

    def select_template(self, template_id: str | int, template_data: dict[str, Any] | None = None) -> TemplateProfile:
        normalized_template_id = str(template_id)
        if template_data is not None:
            profile = self._build_inline_template_profile(normalized_template_id, template_data)
            self._selected_template_profile = profile
            self.runtime_state.selected_template_id = template_id
            self.runtime_state.selected_template_name = profile.name
            self.runtime_state.selected_template_updated_at = time.time()
            self.runtime_state.last_compose_feedback = None
            return profile

        if not self.template_service.select_template(normalized_template_id):
            raise ValueError(f"template not found: {template_id}")

        profile = self.template_service.get_selected_template()
        if profile is None:
            raise ValueError(f"template selected but unavailable: {template_id}")

        self._selected_template_profile = profile
        self.runtime_state.selected_template_id = template_id
        self.runtime_state.selected_template_name = profile.name
        self.runtime_state.selected_template_updated_at = time.time()
        self.runtime_state.last_compose_feedback = None
        return profile

    def clear_template(self) -> None:
        self.template_service.clear_selected_template()
        self._selected_template_profile = None
        self.runtime_state.selected_template_id = None
        self.runtime_state.selected_template_name = None
        self.runtime_state.selected_template_updated_at = time.time()
        self.runtime_state.last_compose_feedback = None

    def _build_inline_template_profile(
        self,
        template_id: str,
        template_data: dict[str, Any],
    ) -> TemplateProfile:
        pose_points = self._normalize_pose_map(template_data.get("pose_points"))
        pose_points_image = self._normalize_pose_map(
            template_data.get("pose_points_image") or template_data.get("pose_points")
        )
        pose_points_bbox = self._normalize_pose_map(template_data.get("pose_points_bbox"))
        bbox_norm = self._normalize_bbox_norm(template_data.get("bbox_norm"))
        area_ratio = self._coerce_float(
            template_data.get("area_ratio"),
            default=max(0.01, bbox_norm[2] * bbox_norm[3]) if bbox_norm[2] > 0 and bbox_norm[3] > 0 else 0.18,
        )
        name = str(template_data.get("name") or f"template_{template_id}")

        return TemplateProfile(
            template_id=template_id,
            name=name,
            image_path=str(template_data.get("source_image_url") or template_data.get("image_path") or ""),
            created_at=time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()),
            anchor_norm_x=self._coerce_float(
                template_data.get("anchor_norm_x", template_data.get("shoulder_anchor_norm_x")),
                default=0.5,
            ),
            anchor_norm_y=self._coerce_float(
                template_data.get("anchor_norm_y", template_data.get("shoulder_anchor_norm_y")),
                default=0.5,
            ),
            shoulder_anchor_norm_x=self._coerce_float(
                template_data.get("shoulder_anchor_norm_x", template_data.get("anchor_norm_x")),
                default=0.5,
            ),
            shoulder_anchor_norm_y=self._coerce_float(
                template_data.get("shoulder_anchor_norm_y", template_data.get("anchor_norm_y")),
                default=0.5,
            ),
            head_anchor_norm_x=self._coerce_optional_float(template_data.get("head_anchor_norm_x")),
            head_anchor_norm_y=self._coerce_optional_float(template_data.get("head_anchor_norm_y")),
            face_anchor_norm_x=self._coerce_optional_float(template_data.get("face_anchor_norm_x")),
            face_anchor_norm_y=self._coerce_optional_float(template_data.get("face_anchor_norm_y")),
            area_ratio=area_ratio,
            facing_sign=self._coerce_float(template_data.get("facing_sign"), default=0.0),
            pose_points=pose_points,
            pose_points_image=pose_points_image,
            pose_points_bbox=pose_points_bbox,
            bbox_norm=bbox_norm,
        )

    @staticmethod
    def _normalize_pose_map(raw_points: Any) -> dict[int, tuple[float, float]]:
        if not isinstance(raw_points, dict):
            return {}
        normalized: dict[int, tuple[float, float]] = {}
        for raw_key, raw_value in raw_points.items():
            if not isinstance(raw_value, (list, tuple)) or len(raw_value) != 2:
                continue
            try:
                key = int(raw_key)
                x = float(raw_value[0])
                y = float(raw_value[1])
            except (TypeError, ValueError):
                continue
            normalized[key] = (x, y)
        return normalized

    @staticmethod
    def _normalize_bbox_norm(raw_bbox: Any) -> tuple[float, float, float, float]:
        if isinstance(raw_bbox, (list, tuple)) and len(raw_bbox) == 4:
            try:
                x, y, w, h = [float(v) for v in raw_bbox]
                return (
                    max(0.0, min(1.0, x)),
                    max(0.0, min(1.0, y)),
                    max(0.0, min(1.0, w)),
                    max(0.0, min(1.0, h)),
                )
            except (TypeError, ValueError):
                pass
        return (0.0, 0.0, 0.0, 0.0)

    @staticmethod
    def _coerce_float(raw_value: Any, *, default: float) -> float:
        try:
            return float(raw_value)
        except (TypeError, ValueError):
            return float(default)

    @staticmethod
    def _coerce_optional_float(raw_value: Any) -> float | None:
        try:
            return None if raw_value is None else float(raw_value)
        except (TypeError, ValueError):
            return None

    def _update_ai_lock_fit_score(
        self,
        stable_detection,
        frame_shape: tuple[int, int, int],
    ) -> None:
        if not self.runtime_state.ai_lock_mode_enabled:
            self.runtime_state.ai_lock_fit_score = 0.0
            return

        box = self.runtime_state.ai_lock_target_box_norm
        if box is None:
            self.runtime_state.ai_lock_fit_score = 0.0
            return

        h, w = frame_shape[:2]
        tx, ty, tw, th = box
        ax1, ay1 = tx * w, ty * h
        aw, ah = max(2.0, tw * w), max(2.0, th * h)
        ax2, ay2 = ax1 + aw, ay1 + ah

        bbox = stable_detection.bbox
        bx1, by1 = float(bbox.x), float(bbox.y)
        bw, bh = float(max(1, bbox.w)), float(max(1, bbox.h))
        bx2, by2 = bx1 + bw, by1 + bh

        ix1, iy1 = max(ax1, bx1), max(ay1, by1)
        ix2, iy2 = min(ax2, bx2), min(ay2, by2)
        iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)
        inter = iw * ih
        union = aw * ah + bw * bh - inter
        self.runtime_state.ai_lock_fit_score = max(0.0, min(1.0, inter / union)) if union > 1e-6 else 0.0

    def _acquire_frame_for_capture(self):
        for _ in range(10):
            frame = self.runtime_state.latest_frame
            if frame is not None:
                return frame

            frame = self.source.read()
            if frame is not None:
                self.runtime_state.latest_frame = frame.copy()
                self.runtime_state.last_frame_at = time.time()
                return frame

            time.sleep(0.05)
        return None

    def _read_frame_for_ai(self):
        frame = self.runtime_state.latest_frame
        if frame is not None:
            return frame
        return self._acquire_frame_for_capture()

    def _capture_frame_for_save(self, frame):
        out = frame.copy()
        if self.mirror_view:
            out = cv2.flip(out, 1)
        return out


class SessionManager:
    """Single-session manager for first device runtime API version."""

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._session: DeviceSessionContext | None = None
        self.template_library = TemplateLibrary()
        self.template_repository = LocalTemplateRepository(self.template_library)
        self.template_service = TemplateService(
            repository=self.template_repository,
            runtime_state=None,
        )
        self._default_selected_template_id: str | None = None

    def open_session(self, payload: SessionOpenPayload) -> DeviceSessionContext:
        with self._lock:
            if self._session is not None:
                self._session.close()
            session = DeviceSessionContext(
                payload,
                template_library=self.template_library,
                template_repository=self.template_repository,
                initial_selected_template_id=self._default_selected_template_id,
            )
            session.start()
            self._session = session
            return session

    def current_session(self) -> DeviceSessionContext | None:
        with self._lock:
            return self._session

    def close_session(self) -> bool:
        with self._lock:
            if self._session is None:
                return False
            self._session.close()
            self._session = None
            return True

    def list_templates(self) -> list[TemplateProfile]:
        with self._lock:
            return self.template_service.list_templates()

    def import_template(self, image_path: str, name: str | None = None) -> TemplateProfile:
        with self._lock:
            return self.template_service.import_template(image_path, name=name)

    def delete_template(self, template_id: str) -> bool:
        with self._lock:
            removed = self.template_service.delete_template(template_id)
            if not removed:
                return False
            if self._default_selected_template_id == template_id:
                self._default_selected_template_id = None
            if self._session is not None and str(self._session.runtime_state.selected_template_id) == template_id:
                self._session._selected_template_profile = None
                self._session.runtime_state.selected_template_id = None
                self._session.runtime_state.selected_template_name = None
                self._session.runtime_state.selected_template_updated_at = time.time()
                self._session.runtime_state.last_compose_feedback = None
            return True

    def select_template(
        self,
        template_id: str | int,
        template_data: dict[str, Any] | None = None,
    ) -> TemplateProfile:
        normalized_template_id = str(template_id)
        with self._lock:
            if template_data is not None:
                if self._session is None:
                    raise ValueError("inline template selection requires an opened session")
                profile = self._session.select_template(
                    normalized_template_id,
                    template_data=template_data,
                )
                self._default_selected_template_id = normalized_template_id
                return profile

            profile = self.template_repository.get(normalized_template_id)
            if profile is None:
                raise ValueError(f"template not found: {template_id}")

            self._default_selected_template_id = normalized_template_id
            if self._session is not None:
                self._session.select_template(normalized_template_id)
            return profile

    def clear_selected_template(self) -> None:
        with self._lock:
            self._default_selected_template_id = None
            self.template_service.clear_selected_template()
            if self._session is not None:
                self._session.clear_template()

    def get_default_selected_template_id(self) -> str | None:
        with self._lock:
            return self._default_selected_template_id


session_manager = SessionManager()
