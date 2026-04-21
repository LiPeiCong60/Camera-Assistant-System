"""Minimal realtime session manager for device runtime local API."""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass
from typing import Any

import cv2

from device_runtime.config import default_config
from device_runtime.control.gimbal_controller import GimbalController, MockServoDriver
from device_runtime.control.tracking_controller import TrackingController
from device_runtime.interfaces.capture_trigger import LocalFileCaptureTrigger
from device_runtime.interfaces.target_strategy import TargetPreset, build_target_strategy
from device_runtime.services.capture_service import CaptureResult, CaptureService
from device_runtime.mode_manager import ControlMode, ModeManager
from device_runtime.services.control_service import ControlService
from device_runtime.services.frame_processor import FrameProcessor
from device_runtime.services.runtime_state import RuntimeState
from device_runtime.services.template_service import TemplateService
from device_runtime.repositories.local_template_repository import LocalTemplateRepository
from device_runtime.templates.template_compose import TemplateLibrary, TemplateProfile
from device_runtime.vision.detector import AsyncDetector, build_runtime_detector
from device_runtime.vision.video_source import OpenCVVideoSource


@dataclass(slots=True)
class SessionOpenPayload:
    session_code: str
    stream_url: str
    mirror_view: bool = True
    start_mode: str = "MANUAL"


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
        self.session_code = payload.session_code
        self.stream_url = payload.stream_url
        self.mirror_view = bool(payload.mirror_view)
        self.opened_at = time.time()

        self.config = default_config(payload.stream_url)
        self.runtime_state = RuntimeState()
        self.mode_manager = ModeManager(initial_mode=ControlMode(payload.start_mode))
        self.tracking = TrackingController(
            self.config.tracking,
            build_target_strategy(TargetPreset.CENTER),
        )
        self.gimbal = GimbalController(self.config.gimbal, MockServoDriver())
        self.control_service = ControlService(
            mode_manager=self.mode_manager,
            tracking=self.tracking,
            gimbal=self.gimbal,
            runtime_state=self.runtime_state,
            manual_step_deg=self.config.app.manual_step_deg,
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
        self.capture_service = CaptureService(
            capture_trigger=self.capture_trigger,
            runtime_state=self.runtime_state,
        )

        self.source = OpenCVVideoSource(self.config.video)
        self._async_detector: AsyncDetector | None = None
        self._frame_processor: FrameProcessor | None = None
        self._detector_interval_s = 1.0 / max(1.0, self.config.detection.detector_fps)
        self._last_submit_ts = 0.0
        self._stop_event = threading.Event()
        self._frame_thread: threading.Thread | None = None
        self._lock = threading.RLock()
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
        self.source = OpenCVVideoSource(self.config.video)
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
        self.gimbal.close()

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
        }

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
                compose_auto_control=False,
                ai_lock_mode_enabled=self.runtime_state.ai_lock_mode_enabled,
                now=now,
            )
            if processed.stable_detection is not None:
                self.runtime_state.last_detection_at = now
                self._update_ai_lock_fit_score(processed.stable_detection, frame.shape)

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

    def trigger_capture(self, *, reason: str) -> CaptureResult:
        frame = self.runtime_state.latest_frame
        if frame is None:
            frame = self._acquire_frame_for_capture()
        if frame is None:
            raise ValueError("no frame available for capture")
        return self.capture_service.capture(
            frame=frame,
            metadata={"reason": reason, "session_code": self.session_code},
            suffix=reason,
            auto_analyze=False,
        )

    def get_preview_jpeg_bytes(self) -> bytes:
        frame = self.runtime_state.latest_frame
        if frame is None:
            frame = self._acquire_frame_for_capture()
        if frame is None:
            raise ValueError("no frame available for preview")

        success, encoded = cv2.imencode(".jpg", frame)
        if not success:
            raise ValueError("failed to encode preview frame")
        return encoded.tobytes()

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

    def get_default_selected_template_id(self) -> str | None:
        with self._lock:
            return self._default_selected_template_id


session_manager = SessionManager()
