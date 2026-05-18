from __future__ import annotations

import logging
import threading
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass

from device_runtime.config import GimbalConfig, ServoAxisConfig


@dataclass(slots=True)
class GimbalState:
    pan_command_angle: float
    tilt_command_angle: float
    pan_feedback_angle: float
    tilt_feedback_angle: float
    feedback_valid: bool = False


class ServoDriver(ABC):
    @abstractmethod
    def write_angle(self, axis: str, angle_deg: float, axis_cfg: ServoAxisConfig) -> None:
        raise NotImplementedError

    def write_angles(
        self,
        angles: dict[str, float],
        axis_configs: dict[str, ServoAxisConfig],
    ) -> None:
        for axis, angle_deg in angles.items():
            self.write_angle(axis, angle_deg, axis_configs[axis])

    @abstractmethod
    def read_angle(self, axis: str, axis_cfg: ServoAxisConfig) -> float | None:
        raise NotImplementedError

    def set_move_time_ms(self, ms: int) -> None:
        pass

    @abstractmethod
    def close(self) -> None:
        raise NotImplementedError


class MockServoDriver(ServoDriver):
    def __init__(self) -> None:
        self._logger = logging.getLogger(self.__class__.__name__)
        self._angles = {"pan": 0.0, "tilt": 0.0}

    def write_angle(self, axis: str, angle_deg: float, axis_cfg: ServoAxisConfig) -> None:
        self._angles[axis] = angle_deg
        self._logger.debug("[MOCK] axis=%s angle=%.2f", axis, angle_deg)

    def read_angle(self, axis: str, axis_cfg: ServoAxisConfig) -> float | None:
        return self._angles.get(axis)

    def close(self) -> None:
        return


class TTLBusSerialDriver(ServoDriver):
    """
    TTL bus-servo driver over serial port.
    Frame format follows controller command style:
    {G0000#000P1500T1500!#001P1500T1500!}
    """

    def __init__(
        self,
        *,
        port: str,
        baudrate: int = 115200,
        move_time_ms: int = 120,
        timeout_s: float = 0.2,
    ) -> None:
        try:
            import serial
        except ImportError as exc:
            raise RuntimeError("Missing dependency pyserial. Install requirements first.") from exc

        self._logger = logging.getLogger(self.__class__.__name__)
        self._serial = serial.Serial(
            port=port,
            baudrate=baudrate,
            timeout=timeout_s,
            write_timeout=timeout_s,
        )
        self._move_time_ms = max(20, int(move_time_ms))
        self._angles: dict[str, float] = {"pan": 0.0, "tilt": 0.0}
        self._pulses_by_id: dict[int, int] = {}
        self._id_by_axis: dict[str, int] = {}

    def write_angle(self, axis: str, angle_deg: float, axis_cfg: ServoAxisConfig) -> None:
        servo_id = axis_cfg.servo_id
        pulse = self._angle_to_pulse(angle_deg, axis_cfg)

        self._angles[axis] = angle_deg
        self._id_by_axis[axis] = servo_id
        self._pulses_by_id[servo_id] = pulse

        frame = self._build_group_frame(self._pulses_by_id, self._move_time_ms)
        self._serial.write(frame.encode("ascii"))
        self._serial.flush()
        self._logger.debug(
            "[TTL] axis=%s servo_id=%03d angle=%.2f pulse=%d frame=%s",
            axis,
            servo_id,
            angle_deg,
            pulse,
            frame.strip(),
        )

    def write_angles(
        self,
        angles: dict[str, float],
        axis_configs: dict[str, ServoAxisConfig],
    ) -> None:
        updated: list[tuple[str, int, float, int]] = []
        for axis, angle_deg in angles.items():
            axis_cfg = axis_configs[axis]
            servo_id = axis_cfg.servo_id
            pulse = self._angle_to_pulse(angle_deg, axis_cfg)
            self._angles[axis] = angle_deg
            self._id_by_axis[axis] = servo_id
            self._pulses_by_id[servo_id] = pulse
            updated.append((axis, servo_id, angle_deg, pulse))

        frame = self._build_group_frame(self._pulses_by_id, self._move_time_ms)
        self._serial.write(frame.encode("ascii"))
        self._serial.flush()
        for axis, servo_id, angle_deg, pulse in updated:
            self._logger.debug(
                "[TTL] axis=%s servo_id=%03d angle=%.2f pulse=%d frame=%s",
                axis,
                servo_id,
                angle_deg,
                pulse,
                frame.strip(),
            )

    def set_move_time_ms(self, ms: int) -> None:
        self._move_time_ms = max(20, int(ms))

    def read_angle(self, axis: str, axis_cfg: ServoAxisConfig) -> float | None:
        return self._angles.get(axis)

    def close(self) -> None:
        if self._serial.is_open:
            self._serial.close()

    @staticmethod
    def _angle_to_pulse(angle_deg: float, axis_cfg: ServoAxisConfig) -> int:
        span = axis_cfg.max_angle - axis_cfg.min_angle
        if span <= 0:
            raise ValueError(
                f"Invalid axis range: min={axis_cfg.min_angle}, max={axis_cfg.max_angle}"
            )
        clamped = min(axis_cfg.max_angle, max(axis_cfg.min_angle, angle_deg))
        normalized = (clamped - axis_cfg.min_angle) / span
        pulse = int(round(500 + normalized * 2000))
        return min(2500, max(500, pulse))

    @staticmethod
    def _build_group_frame(pulses_by_id: dict[int, int], move_time_ms: int) -> str:
        if not pulses_by_id:
            return "{G0000!}\r\n"
        parts = [f"#{sid:03d}P{pulse:04d}T{move_time_ms:04d}!" for sid, pulse in sorted(pulses_by_id.items())]
        return "{G0000" + "".join(parts) + "}\r\n"


class GimbalController:
    def __init__(self, config: GimbalConfig, driver: ServoDriver) -> None:
        self._config = config
        self._driver = driver
        self._logger = logging.getLogger(self.__class__.__name__)
        self._lock = threading.RLock()
        self._stop_feedback_event = threading.Event()
        self._feedback_thread: threading.Thread | None = None
        self._live_thread: threading.Thread | None = None
        self._live_pan_rate_dps = 0.0
        self._live_tilt_rate_dps = 0.0
        self._live_until = 0.0
        self._tracking_pan_target: float | None = None
        self._tracking_tilt_target: float | None = None
        self._tracking_until = 0.0
        self._state = GimbalState(
            pan_command_angle=config.pan.home_angle,
            tilt_command_angle=config.tilt.home_angle,
            pan_feedback_angle=config.pan.home_angle,
            tilt_feedback_angle=config.tilt.home_angle,
        )
        self.set_absolute(
            self._state.pan_command_angle, self._state.tilt_command_angle, smooth=False
        )
        self.refresh_feedback()
        self._start_feedback_loop()

    @property
    def state(self) -> GimbalState:
        with self._lock:
            return GimbalState(
                pan_command_angle=self._state.pan_command_angle,
                tilt_command_angle=self._state.tilt_command_angle,
                pan_feedback_angle=self._state.pan_feedback_angle,
                tilt_feedback_angle=self._state.tilt_feedback_angle,
                feedback_valid=self._state.feedback_valid,
            )

    def home(self) -> None:
        with self._lock:
            self.set_absolute(
                self._config.pan.home_angle, self._config.tilt.home_angle, smooth=False
            )

    def set_absolute(self, pan: float, tilt: float, smooth: bool = True) -> None:
        with self._lock:
            self._clear_live_motion_locked()
            self._clear_tracking_motion_locked()
            pan = self._clamp(pan, self._config.pan)
            tilt = self._clamp(tilt, self._config.tilt)

            if not smooth:
                self._apply(pan, tilt)
                return

            pan_step = max(1e-6, abs(self._config.pan.max_step_deg))
            tilt_step = max(1e-6, abs(self._config.tilt.max_step_deg))
            # Set move time once before the loop; each sub-step takes the full
            # configured duration so the servo completes before the next command.
            self._driver.set_move_time_ms(self._config.ttl_bus.move_time_ms)
            current_pan, current_tilt = self.get_current_angles(prefer_feedback=True)
            while True:
                next_pan = self._step_towards(current_pan, pan, pan_step)
                next_tilt = self._step_towards(current_tilt, tilt, tilt_step)

                self._apply(next_pan, next_tilt)

                done_pan = abs(next_pan - pan) < 1e-3
                done_tilt = abs(next_tilt - tilt) < 1e-3
                if done_pan and done_tilt:
                    break
                current_pan, current_tilt = self.get_current_angles(prefer_feedback=True)
                # Wait for the servo to finish this sub-step before sending next,
                # preventing command stacking and jerky motion.
                time.sleep(self._config.ttl_bus.move_time_ms / 1000.0)

    def move_relative(self, pan_delta: float, tilt_delta: float, smooth: bool = True) -> None:
        with self._lock:
            current_pan, current_tilt = self.get_current_angles(prefer_feedback=True)
            self.set_absolute(
                pan=current_pan + pan_delta,
                tilt=current_tilt + tilt_delta,
                smooth=smooth,
            )

    def move_relative_live(self, pan_delta: float, tilt_delta: float) -> None:
        """Refresh continuous velocity motion for manual control loops."""
        with self._lock:
            self._clear_tracking_motion_locked()
            command_interval_s = max(0.02, float(self._config.live_command_interval_s))
            max_rate_pan = abs(self._config.pan.max_step_deg) / max(
                0.01,
                float(self._config.live_control_interval_s),
            )
            max_rate_tilt = abs(self._config.tilt.max_step_deg) / max(
                0.01,
                float(self._config.live_control_interval_s),
            )
            self._live_pan_rate_dps = self._limit_delta(
                pan_delta / command_interval_s,
                max_rate_pan,
            )
            self._live_tilt_rate_dps = self._limit_delta(
                tilt_delta / command_interval_s,
                max_rate_tilt,
            )
            self._live_until = time.monotonic() + max(
                command_interval_s * 1.4,
                float(self._config.live_command_hold_s),
            )
            self._driver.set_move_time_ms(self._config.ttl_bus.move_time_ms)
            self._start_live_loop_locked()

    def move_relative_step_live(self, pan_delta: float, tilt_delta: float) -> None:
        """Ease toward one bounded correction for tracking loops."""
        with self._lock:
            self._clear_live_motion_locked()
            pan_delta = self._limit_delta(pan_delta, self._config.pan.max_step_deg)
            tilt_delta = self._limit_delta(tilt_delta, self._config.tilt.max_step_deg)
            self._tracking_pan_target = self._clamp(
                self._state.pan_command_angle + pan_delta,
                self._config.pan,
            )
            self._tracking_tilt_target = self._clamp(
                self._state.tilt_command_angle + tilt_delta,
                self._config.tilt,
            )
            self._tracking_until = time.monotonic() + max(
                float(self._config.tracking_target_hold_s),
                float(self._config.live_command_interval_s) * 2.0,
            )
            self._driver.set_move_time_ms(self._config.ttl_bus.move_time_ms)
            self._start_live_loop_locked()

    def refresh_feedback(self) -> GimbalState:
        with self._lock:
            pan = self._driver.read_angle("pan", self._config.pan)
            tilt = self._driver.read_angle("tilt", self._config.tilt)
            if pan is None or tilt is None:
                self._state.feedback_valid = False
                return self.state

            self._state.pan_feedback_angle = self._clamp(pan, self._config.pan)
            self._state.tilt_feedback_angle = self._clamp(tilt, self._config.tilt)
            self._state.feedback_valid = True
            return self.state

    def get_current_angles(self, prefer_feedback: bool = True) -> tuple[float, float]:
        with self._lock:
            if prefer_feedback:
                state = self.refresh_feedback()
                if state.feedback_valid:
                    return state.pan_feedback_angle, state.tilt_feedback_angle
            return self._state.pan_command_angle, self._state.tilt_command_angle

    def close(self) -> None:
        self._stop_feedback_event.set()
        if self._live_thread is not None:
            self._live_thread.join(timeout=1.0)
        if self._feedback_thread is not None:
            self._feedback_thread.join(timeout=1.0)
        with self._lock:
            self._driver.close()

    def _apply(self, pan: float, tilt: float) -> None:
        self._driver.write_angles(
            {"pan": pan, "tilt": tilt},
            {"pan": self._config.pan, "tilt": self._config.tilt},
        )
        self._state.pan_command_angle = pan
        self._state.tilt_command_angle = tilt
        self.refresh_feedback()
        self._logger.debug("gimbal pan=%.2f tilt=%.2f", pan, tilt)

    @staticmethod
    def _clamp(value: float, axis_cfg: ServoAxisConfig) -> float:
        return min(axis_cfg.max_angle, max(axis_cfg.min_angle, value))

    @staticmethod
    def _step_towards(current: float, target: float, max_step: float) -> float:
        if abs(target - current) <= max_step:
            return target
        return current + max_step if target > current else current - max_step

    @staticmethod
    def _limit_delta(delta: float, max_step: float) -> float:
        limit = max(1e-6, abs(max_step))
        return min(limit, max(-limit, delta))

    def _clear_live_motion_locked(self) -> None:
        self._live_pan_rate_dps = 0.0
        self._live_tilt_rate_dps = 0.0
        self._live_until = 0.0

    def _clear_tracking_motion_locked(self) -> None:
        self._tracking_pan_target = None
        self._tracking_tilt_target = None
        self._tracking_until = 0.0

    def _start_live_loop_locked(self) -> None:
        if self._live_thread is not None and self._live_thread.is_alive():
            return
        self._live_thread = threading.Thread(
            target=self._live_worker,
            name="gimbal-live-control-loop",
            daemon=True,
        )
        self._live_thread.start()

    def _live_worker(self) -> None:
        interval_s = max(0.015, float(self._config.live_control_interval_s))
        last_ts = time.monotonic()
        while not self._stop_feedback_event.is_set():
            now = time.monotonic()
            dt = min(0.08, max(0.0, now - last_ts))
            last_ts = now
            sleep_s = interval_s

            try:
                with self._lock:
                    if now > self._live_until:
                        self._clear_live_motion_locked()
                    pan_rate = self._live_pan_rate_dps
                    tilt_rate = self._live_tilt_rate_dps
                    if abs(pan_rate) > 1e-3 or abs(tilt_rate) > 1e-3:
                        pan_step = self._limit_delta(
                            pan_rate * dt,
                            self._config.pan.max_step_deg,
                        )
                        tilt_step = self._limit_delta(
                            tilt_rate * dt,
                            self._config.tilt.max_step_deg,
                        )
                        pan = self._clamp(
                            self._state.pan_command_angle + pan_step,
                            self._config.pan,
                        )
                        tilt = self._clamp(
                            self._state.tilt_command_angle + tilt_step,
                            self._config.tilt,
                        )
                        self._apply(pan, tilt)
                    elif (
                        self._tracking_pan_target is not None
                        and self._tracking_tilt_target is not None
                    ):
                        if now > self._tracking_until:
                            self._clear_tracking_motion_locked()
                            continue
                        pan = self._next_eased_angle(
                            self._state.pan_command_angle,
                            self._tracking_pan_target,
                            self._config.pan.max_step_deg,
                        )
                        tilt = self._next_eased_angle(
                            self._state.tilt_command_angle,
                            self._tracking_tilt_target,
                            self._config.tilt.max_step_deg,
                        )
                        done_pan = abs(pan - self._tracking_pan_target) < 0.02
                        done_tilt = abs(tilt - self._tracking_tilt_target) < 0.02
                        self._apply(pan, tilt)
                        if done_pan and done_tilt:
                            self._clear_tracking_motion_locked()
            except Exception:
                self._logger.exception("Failed to apply live gimbal motion.")

            time.sleep(sleep_s)

    def _next_eased_angle(self, current: float, target: float, max_step: float) -> float:
        diff = target - current
        if abs(diff) < 0.02:
            return target
        alpha = min(0.75, max(0.15, float(self._config.tracking_ease_alpha)))
        step = self._limit_delta(diff * alpha, max(0.12, abs(max_step) * 0.9))
        if abs(step) > abs(diff):
            return target
        return current + step

    def _start_feedback_loop(self) -> None:
        if self._feedback_thread is not None:
            return
        self._feedback_thread = threading.Thread(
            target=self._feedback_worker,
            name="gimbal-feedback-loop",
            daemon=True,
        )
        self._feedback_thread.start()

    def _feedback_worker(self) -> None:
        while not self._stop_feedback_event.is_set():
            try:
                self.refresh_feedback()
            except Exception:
                self._logger.exception("Failed to refresh gimbal feedback angle.")
            time.sleep(max(0.01, self._config.feedback_poll_interval_s))
