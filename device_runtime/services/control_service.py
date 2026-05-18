"""
控制服务模块
负责处理云台控制命令、模式切换等基础控制功能
"""

import time
from typing import Callable, Optional

from device_runtime.control.gimbal_controller import GimbalController
from device_runtime.control.tracking_controller import TrackingController
from device_runtime.mode_manager import ControlMode, ModeManager
from device_runtime.services.runtime_state import RuntimeState
from device_runtime.utils.common_types import GimbalCommand
from device_runtime.utils.ui_text import (
    FOLLOW_TEXT,
    SPEED_TEXT,
    follow_mode_to_target_type,
    normalize_follow_mode,
)


class ControlService:
    """控制服务类，封装所有控制相关逻辑"""

    def __init__(
        self,
        mode_manager: ModeManager,
        tracking: TrackingController,
        gimbal: GimbalController,
        runtime_state: RuntimeState,
        manual_step_deg: float = 2.0,
    ) -> None:
        self._mode_manager = mode_manager
        self._tracking = tracking
        self._gimbal = gimbal
        self._runtime_state = runtime_state
        self._manual_step_deg = manual_step_deg

    def execute_command(
        self,
        command: str,
        *,
        notify: Optional[Callable[[str], None]] = None,
        set_follow_mode: Optional[Callable[[str], None]] = None,
        set_speed_mode: Optional[Callable[[str], None]] = None,
        stop_event=None,
    ) -> None:
        """执行控制命令"""
        if notify:
            notify(f"> {command}")

        if command.strip().lower() == "capture":
            # 抓拍命令由专门的 capture service 处理
            return

        # 将命令处理委托给 app_core 的 process_command
        from device_runtime.app_core import process_command
        try:
            process_command(
                command,
                mode_manager=self._mode_manager,
                tracking=self._tracking,
                gimbal=self._gimbal,
                capture_trigger=None,  # 由 capture service 处理
                manual_step_deg=self._manual_step_deg,
                stop_event=stop_event,
                notify=notify or (lambda x: None),
                set_follow_mode=set_follow_mode or self.set_follow_mode,
                set_speed_mode=set_speed_mode or self.set_speed_mode,
            )
        except Exception as exc:
            if notify:
                notify(f"命令执行失败: {exc}")

    def get_mode(self) -> ControlMode:
        """获取当前模式"""
        return self._mode_manager.mode

    def set_mode(self, mode: ControlMode) -> None:
        """设置模式"""
        self._mode_manager.set_mode(mode)

    def get_follow_mode(self) -> str:
        """获取跟随模式"""
        return self._runtime_state.follow_mode

    def set_follow_mode(self, mode: str) -> None:
        """设置跟随模式"""
        normalized = normalize_follow_mode(mode)
        if normalized not in FOLLOW_TEXT:
            raise ValueError(f"不支持的跟随模式: {mode}")
        self._runtime_state.follow_mode = normalized

    def get_speed_mode(self) -> str:
        """获取速度模式"""
        return self._runtime_state.speed_mode

    def set_speed_mode(self, mode: str) -> None:
        """设置速度模式"""
        if mode not in SPEED_TEXT:
            raise ValueError(f"不支持的速度模式: {mode}")
        self._runtime_state.speed_mode = mode
        self._tracking.set_speed_mode(mode)

    def get_sensitivity(self) -> float:
        """获取跟踪灵敏度"""
        return float(self._tracking._config.sensitivity)

    def set_sensitivity(self, value: float) -> None:
        """设置跟踪灵敏度（影响自动跟随、模板构图和手动控制）"""
        self._tracking.set_sensitivity(value)

    def manual_move(self, action: str) -> None:
        """手动移动云台"""
        sensitivity = float(self._tracking._config.sensitivity)
        step = self._manual_step_deg * sensitivity
        normalized = action.strip().lower()
        if normalized in {"w", "up"}:
            self._move_live(0.0, -step)
            return
        if normalized in {"s", "down"}:
            self._move_live(0.0, step)
            return
        if normalized in {"a", "left"}:
            self._move_live(-step, 0.0)
            return
        if normalized in {"d", "right"}:
            self._move_live(step, 0.0)
            return
        raise ValueError(f"不支持的手动控制动作: {action}")

    def move_relative(self, pan_delta: float, tilt_delta: float, smooth: bool = True) -> None:
        """相对移动"""
        if smooth:
            self._gimbal.move_relative(pan_delta, tilt_delta, smooth=True)
            return
        self._move_live(pan_delta, tilt_delta)

    def set_absolute(self, pan: float, tilt: float, smooth: bool = True) -> None:
        """绝对定位"""
        self._gimbal.set_absolute(pan, tilt, smooth)

    def home(self) -> None:
        """回中"""
        self._gimbal.home()

    def get_current_angles(self, prefer_feedback: bool = True) -> tuple[float, float]:
        """获取当前角度"""
        return self._gimbal.get_current_angles(prefer_feedback=prefer_feedback)

    def get_follow_target_type(self) -> str:
        return follow_mode_to_target_type(self._runtime_state.follow_mode)

    def track_target(
        self,
        target_x: float,
        target_y: float,
        *,
        desired_x: float = 0.5,
        desired_y: float = 0.5,
        target_type: str = "shoulder_center",
        confidence: float = 1.0,
        frame: dict | None = None,
    ) -> GimbalCommand | None:
        normalized_follow_mode = normalize_follow_mode(target_type)
        if normalized_follow_mode not in FOLLOW_TEXT:
            raise ValueError(f"unsupported target_type: {target_type}")
        self._runtime_state.follow_mode = normalized_follow_mode

        clamped_x = self._clamp01(target_x)
        clamped_y = self._clamp01(target_y)
        clamped_desired_x = self._clamp01(desired_x)
        clamped_desired_y = self._clamp01(desired_y)
        clamped_confidence = self._clamp01(confidence)
        frame_shape = self._frame_shape_from_metadata(frame)

        command = self._tracking.compute_external_command(
            frame_shape,
            target_x_norm=clamped_x,
            target_y_norm=clamped_y,
            desired_x_norm=clamped_desired_x,
            desired_y_norm=clamped_desired_y,
            confidence=clamped_confidence,
        )
        if command is None:
            return None
        self._runtime_state.external_track_control_until = time.time() + 0.18
        self._move_tracking_step(command.pan_delta, command.tilt_delta)
        return command

    def _move_live(self, pan_delta: float, tilt_delta: float) -> None:
        move_live = getattr(self._gimbal, "move_relative_live", None)
        if callable(move_live):
            move_live(pan_delta, tilt_delta)
            return
        self._gimbal.move_relative(pan_delta, tilt_delta, smooth=False)

    def _move_tracking_step(self, pan_delta: float, tilt_delta: float) -> None:
        move_step = getattr(self._gimbal, "move_relative_step_live", None)
        if callable(move_step):
            move_step(pan_delta, tilt_delta)
            return
        self._gimbal.move_relative(pan_delta, tilt_delta, smooth=False)

    @staticmethod
    def _clamp01(value: float) -> float:
        return max(0.0, min(1.0, float(value)))

    @staticmethod
    def _frame_shape_from_metadata(frame: dict | None) -> tuple[int, int, int]:
        width = height = None
        if isinstance(frame, dict):
            width = frame.get("width")
            height = frame.get("height")
        try:
            parsed_width = int(width) if width is not None else 1000
            parsed_height = int(height) if height is not None else 1000
        except (TypeError, ValueError):
            parsed_width = 1000
            parsed_height = 1000
        return (max(1, parsed_height), max(1, parsed_width), 3)
