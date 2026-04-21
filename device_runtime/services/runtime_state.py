from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from device_runtime.utils.common_types import DetectionResult, VisionResult


@dataclass(slots=True)
class RuntimeState:
    follow_mode: str = "shoulders"
    speed_mode: str = "normal"
    selected_template_id: str | int | None = None
    selected_template_name: str | None = None
    selected_template_updated_at: float | None = None
    reliable_detection_streak: int = 0
    last_compose_feedback: Any | None = None
    ready_since_ts: float = 0.0
    latest_frame: Any = None
    latest_vision: VisionResult | None = None
    stable_detection: DetectionResult | None = None
    latest_capture_path: str | None = None
    latest_capture_analysis: Any | None = None
    latest_capture_error: str | None = None
    ai_angle_search_running: bool = False
    ai_lock_mode_enabled: bool = False
    ai_lock_target_box_norm: tuple[float, float, float, float] | None = None
    ai_lock_fit_score: float = 0.0
    detector_backend: str = "uninitialized"
    last_runtime_error: str | None = None
    last_frame_at: float | None = None
    last_detection_at: float | None = None
    loop_running: bool = False
