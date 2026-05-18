from __future__ import annotations

import time
from math import hypot

from device_runtime.config import TrackingConfig
from device_runtime.interfaces.target_strategy import TargetStrategy
from device_runtime.utils.common_types import DetectionResult, GimbalCommand, Point


class TrackingController:
    """Converts detection offsets to stable gimbal delta commands."""

    def __init__(self, config: TrackingConfig, target_strategy: TargetStrategy) -> None:
        self._config = config
        self._target_strategy = target_strategy
        self._off_center_frames = 0
        self._last_command_ts = 0.0
        self._last_anchor: tuple[float, float] | None = None
        self._last_pan_cmd = 0.0
        self._last_tilt_cmd = 0.0
        self._last_external_command_ts = 0.0
        self._last_external_pan_cmd = 0.0
        self._last_external_tilt_cmd = 0.0
        self._speed_scale = 1.0

    def set_target_strategy(self, strategy: TargetStrategy) -> None:
        self._target_strategy = strategy
        self._off_center_frames = 0

    def set_speed_mode(self, mode: str) -> None:
        speed_map = {"slow": 0.7, "normal": 1.0, "fast": 1.35, "turbo": 1.65}
        self._speed_scale = speed_map.get(mode, speed_map["normal"])

    def set_sensitivity(self, value: float) -> None:
        self._config.sensitivity = max(0.1, min(3.0, float(value)))

    @property
    def settle_after_move_s(self) -> float:
        return float(self._config.settle_after_move_s)

    def get_target_point(self, frame_shape: tuple[int, int, int]) -> tuple[int, int]:
        point = self._target_strategy.get_target_point(frame_shape)
        return int(point.x), int(point.y)

    def compute_command(
        self,
        frame_shape: tuple[int, int, int],
        detection: DetectionResult | None,
        target_override: Point | None = None,
    ) -> GimbalCommand | None:
        if detection is None:
            self._off_center_frames = 0
            self._last_anchor = None
            self._last_pan_cmd = 0.0
            self._last_tilt_cmd = 0.0
            return None

        min_confidence = min(1.0, max(0.0, float(self._config.min_confidence)))
        if float(detection.confidence) < min_confidence:
            self._off_center_frames = 0
            self._last_anchor = None
            self._last_pan_cmd = 0.0
            self._last_tilt_cmd = 0.0
            return None

        target = target_override if target_override is not None else self._target_strategy.get_target_point(frame_shape)
        center = detection.anchor_point if detection.anchor_point is not None else detection.bbox.center
        cx, cy = center.x, center.y

        if self._last_anchor is not None:
            jump = hypot(cx - self._last_anchor[0], cy - self._last_anchor[1])
            if jump > self._config.max_anchor_jump_px:
                # Drop sudden outlier to avoid servo snapping.
                self._last_anchor = (cx, cy)
                return None
            a = min(0.55, max(0.2, self._config.command_smooth_alpha * 1.2))
            cx = self._last_anchor[0] * (1 - a) + cx * a
            cy = self._last_anchor[1] * (1 - a) + cy * a
        self._last_anchor = (cx, cy)

        offset_x = cx - target.x
        offset_y = cy - target.y

        # Use tighter deadzone when precise alignment is needed (e.g. template compose).
        is_precise = target_override is not None
        effective_deadzone = float(self._config.compose_deadzone_px if is_precise else self._config.deadzone_px)

        in_deadzone = (
            abs(offset_x) <= effective_deadzone
            and abs(offset_y) <= effective_deadzone
        )
        if in_deadzone:
            self._off_center_frames = 0
            self._decay_last_command()
            return None

        self._off_center_frames += 1
        if self._off_center_frames < self._config.debounce_frames:
            return None

        now = time.time()
        effective_interval = self._config.min_command_interval_s / max(0.5, self._speed_scale)
        if now - self._last_command_ts < effective_interval:
            return None
        self._last_command_ts = now

        sensitivity = float(self._config.sensitivity)
        raw_pan = self._clamp(offset_x * self._config.gain_x * sensitivity, self._config.max_delta_deg)
        raw_tilt = self._clamp(offset_y * self._config.gain_y * sensitivity, self._config.max_delta_deg)

        # Soft-landing brake zone: reduce gain as we approach the target.
        brake_zone = effective_deadzone * 2.8
        raw_pan = self._apply_brake(raw_pan, offset_x, effective_deadzone, brake_zone)
        raw_tilt = self._apply_brake(raw_tilt, offset_y, effective_deadzone, brake_zone)

        # Sign may vary by hardware mounting direction.
        if not self._config.invert_pan:
            raw_pan = -raw_pan
        if self._config.invert_tilt:
            raw_tilt = -raw_tilt

        # Suppress rapid command sign flips near center to reduce "hunting" jitter.
        reverse_guard_px = effective_deadzone * 1.9
        if self._last_pan_cmd * raw_pan < 0 and abs(offset_x) <= reverse_guard_px:
            raw_pan = 0.0
        if self._last_tilt_cmd * raw_tilt < 0 and abs(offset_y) <= reverse_guard_px:
            raw_tilt = 0.0

        sa = self._config.command_smooth_alpha
        pan_delta = self._last_pan_cmd * (1 - sa) + raw_pan * sa
        tilt_delta = self._last_tilt_cmd * (1 - sa) + raw_tilt * sa
        self._last_pan_cmd = pan_delta
        self._last_tilt_cmd = tilt_delta

        max_delta_limit = self._config.max_delta_deg * max(0.7, self._speed_scale)
        pan_delta = self._clamp(pan_delta * self._speed_scale, max_delta_limit)
        tilt_delta = self._clamp(tilt_delta * self._speed_scale, max_delta_limit)

        if (
            abs(pan_delta) < self._config.min_output_deg
            and abs(tilt_delta) < self._config.min_output_deg
        ):
            return None

        return GimbalCommand(pan_delta=pan_delta, tilt_delta=tilt_delta, reason="auto_track")

    def compute_external_command(
        self,
        frame_shape: tuple[int, int, int],
        *,
        target_x_norm: float,
        target_y_norm: float,
        desired_x_norm: float = 0.5,
        desired_y_norm: float = 0.5,
        confidence: float = 1.0,
    ) -> GimbalCommand | None:
        """Convert a phone-provided normalized target point into a responsive command."""
        min_confidence = min(1.0, max(0.0, float(self._config.min_confidence)))
        if float(confidence) < min_confidence:
            self._decay_external_command()
            return None

        height, width = frame_shape[:2]
        width = max(1, int(width))
        height = max(1, int(height))
        target_x = min(1.0, max(0.0, float(target_x_norm)))
        target_y = min(1.0, max(0.0, float(target_y_norm)))
        desired_x = min(1.0, max(0.0, float(desired_x_norm)))
        desired_y = min(1.0, max(0.0, float(desired_y_norm)))
        offset_x = (target_x - desired_x) * width
        offset_y = (target_y - desired_y) * height

        precise_target = abs(desired_x - 0.5) > 1e-3 or abs(desired_y - 0.5) > 1e-3
        base_deadzone = (
            self._config.compose_deadzone_px if precise_target else self._config.deadzone_px
        )
        deadzone_px = max(14.0, float(base_deadzone) * (1.0 if precise_target else 0.75))
        if abs(offset_x) <= deadzone_px and abs(offset_y) <= deadzone_px:
            self._decay_external_command()
            return None

        now = time.time()
        effective_interval = min(
            0.08,
            self._config.min_command_interval_s / max(0.7, self._speed_scale),
        )
        if now - self._last_external_command_ts < effective_interval:
            return None
        self._last_external_command_ts = now

        sensitivity = float(self._config.sensitivity)
        gain_scale = 1.0 * sensitivity
        max_delta_limit = min(2.2, max(1.0, self._config.max_delta_deg))
        raw_pan = self._clamp(
            offset_x * self._config.gain_x * gain_scale,
            max_delta_limit,
        )
        raw_tilt = self._clamp(
            offset_y * self._config.gain_y * gain_scale,
            max_delta_limit,
        )

        # Soft-landing brake zone for phone-based tracking.
        brake_zone_px = deadzone_px * 3.0
        raw_pan = self._apply_brake(raw_pan, offset_x, deadzone_px, brake_zone_px)
        raw_tilt = self._apply_brake(raw_tilt, offset_y, deadzone_px, brake_zone_px)

        if not self._config.invert_pan:
            raw_pan = -raw_pan
        if self._config.invert_tilt:
            raw_tilt = -raw_tilt

        reverse_guard_px = deadzone_px * 2.4
        if (
            self._last_external_pan_cmd * raw_pan < 0
            and abs(offset_x) <= reverse_guard_px
        ):
            raw_pan = 0.0
        if (
            self._last_external_tilt_cmd * raw_tilt < 0
            and abs(offset_y) <= reverse_guard_px
        ):
            raw_tilt = 0.0

        config_alpha = float(self._config.command_smooth_alpha)
        smooth_alpha = (
            1.0
            if config_alpha >= 1.0
            else max(0.30, min(0.48, config_alpha * 1.2))
        )
        pan_delta = (
            self._last_external_pan_cmd * (1 - smooth_alpha)
            + raw_pan * smooth_alpha
        )
        tilt_delta = (
            self._last_external_tilt_cmd * (1 - smooth_alpha)
            + raw_tilt * smooth_alpha
        )

        max_step_change = max(0.25, max_delta_limit * 0.45)
        pan_delta = self._limit_step(
            pan_delta,
            self._last_external_pan_cmd,
            max_step_change,
        )
        tilt_delta = self._limit_step(
            tilt_delta,
            self._last_external_tilt_cmd,
            max_step_change,
        )

        self._last_external_pan_cmd = pan_delta
        self._last_external_tilt_cmd = tilt_delta

        min_output = max(0.05, float(self._config.min_output_deg) * 0.4)
        if abs(pan_delta) < min_output and abs(tilt_delta) < min_output:
            return None

        return GimbalCommand(
            pan_delta=self._clamp(pan_delta, max_delta_limit),
            tilt_delta=self._clamp(tilt_delta, max_delta_limit),
            reason="phone_track",
        )

    @staticmethod
    def _clamp(value: float, limit: float) -> float:
        return min(limit, max(-limit, value))

    @staticmethod
    def _apply_brake(raw: float, offset: float, deadzone: float, brake_zone: float) -> float:
        """Reduce gain as offset approaches deadzone to prevent overshoot."""
        dist = abs(offset)
        if dist >= brake_zone:
            return raw
        # Linearly ramp gain from 1.0 at brake_zone down to 0.15 at deadzone edge.
        t = max(0.0, (dist - deadzone) / max(1.0, brake_zone - deadzone))
        gain = 0.15 + 0.85 * t
        return raw * gain

    @staticmethod
    def _limit_step(value: float, previous: float, limit: float) -> float:
        if value > previous + limit:
            return previous + limit
        if value < previous - limit:
            return previous - limit
        return value

    def _decay_last_command(self) -> None:
        self._last_pan_cmd *= 0.35
        self._last_tilt_cmd *= 0.35
        if abs(self._last_pan_cmd) < self._config.min_output_deg:
            self._last_pan_cmd = 0.0
        if abs(self._last_tilt_cmd) < self._config.min_output_deg:
            self._last_tilt_cmd = 0.0

    def _decay_external_command(self) -> None:
        self._last_external_pan_cmd *= 0.25
        self._last_external_tilt_cmd *= 0.25
        if abs(self._last_external_pan_cmd) < self._config.min_output_deg:
            self._last_external_pan_cmd = 0.0
        if abs(self._last_external_tilt_cmd) < self._config.min_output_deg:
            self._last_external_tilt_cmd = 0.0
