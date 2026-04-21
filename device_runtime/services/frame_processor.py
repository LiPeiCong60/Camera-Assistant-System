"""
统一的帧处理 Pipeline
抽取 GUI 和 API 共用的实时处理逻辑
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Callable, Optional

from device_runtime.app_core import (
    RELIABLE_STREAK_FOR_TRACKING,
    TargetSelector,
    build_draw_vision,
    reliable_detection,
)
from device_runtime.control.tracking_controller import TrackingController
from device_runtime.mode_manager import ControlMode, ModeManager
from device_runtime.services.runtime_state import RuntimeState
from device_runtime.templates.template_compose import TemplateComposeEngine, TemplateProfile
from device_runtime.utils.common_types import DetectionResult, Point, VisionResult


@dataclass(slots=True)
class ProcessedFrame:
    """帧处理结果"""
    frame: Any  # Original frame (may be resized for inference)
    vision: VisionResult  # Detection result
    stable_detection: DetectionResult | None  # Reliable detection after filtering
    compose_feedback: Any | None  # Template evaluation feedback
    compose_target_override: Point | None  # Template-guided target point
    ready_for_gesture: bool  # Whether ready for gesture capture
    should_auto_move: bool  # Whether should auto-track
    tracking_command: Any | None  # Gimbal command if auto-tracking


class FrameProcessor:
    """
    统一的帧处理器

    职责：
    1. 检测调度与结果筛选
    2. 稳定目标选择
    3. 模板评估（如果在 SMART_COMPOSE 模式）
    4. 跟随命令计算
    5. AI 锁机位 fit score 更新

    不负责：
    - UI 渲染
    - 手势识别
    - 抓拍触发
    - 云台实际移动（只计算命令）
    """

    def __init__(
        self,
        *,
        mode_manager: ModeManager,
        tracking: TrackingController,
        runtime_state: RuntimeState,
        template_engine: Optional[TemplateComposeEngine] = None,
        target_selector: Optional[TargetSelector] = None,
    ) -> None:
        self._mode_manager = mode_manager
        self._tracking = tracking
        self._runtime_state = runtime_state
        self._template_engine = template_engine or TemplateComposeEngine()
        self._target_selector = target_selector or TargetSelector()

        # Internal state
        self._reliable_detection_streak = 0
        self._ready_since_ts = 0.0
        self._tracking_hold_until = 0.0

    def process_frame(
        self,
        frame: Any,
        vision: VisionResult,
        *,
        selected_template: Optional[TemplateProfile] = None,
        mirror_view: bool = False,
        compose_auto_control: bool = False,
        ai_lock_mode_enabled: bool = False,
        now: Optional[float] = None,
    ) -> ProcessedFrame:
        """
        处理单帧

        Args:
            frame: 原始帧
            vision: 检测结果
            selected_template: 当前选中的模板
            mirror_view: 是否镜像视图
            compose_auto_control: 模板引导是否自动转动
            ai_lock_mode_enabled: AI 锁机位是否启用
            now: 当前时间戳（用于测试）

        Returns:
            ProcessedFrame: 处理结果
        """
        if now is None:
            now = time.time()

        # 1. 选择稳定目标
        candidate = self._target_selector.select(vision, self._runtime_state.follow_mode)
        stable = reliable_detection(candidate, frame.shape)

        # 2. 更新可靠检测连续帧计数
        if stable is not None:
            self._reliable_detection_streak += 1
        else:
            self._reliable_detection_streak = 0

        # 3. 更新 runtime_state
        self._runtime_state.latest_vision = vision
        self._runtime_state.stable_detection = stable
        self._runtime_state.reliable_detection_streak = self._reliable_detection_streak

        # 4. 模板评估（仅在 SMART_COMPOSE 模式）
        compose_feedback = None
        compose_target_override = None
        ready_for_gesture = False

        if self._mode_manager.mode == ControlMode.SMART_COMPOSE and selected_template is not None and stable is not None:
            compose_feedback = self._template_engine.evaluate(
                selected_template,
                stable,
                frame.shape,
                mirror_template=mirror_view,
                follow_mode=self._runtime_state.follow_mode,
            )

            # 计算模板引导目标点
            target_x_norm = float(compose_feedback.target_norm[0])
            target_y_norm = float(compose_feedback.target_norm[1])
            if mirror_view:
                target_x_norm = 1.0 - target_x_norm
            compose_target_override = Point(
                x=max(0.0, min(float(frame.shape[1] - 1), target_x_norm * frame.shape[1])),
                y=max(0.0, min(float(frame.shape[0] - 1), target_y_norm * frame.shape[0])),
            )

            # 更新 runtime_state
            self._runtime_state.last_compose_feedback = compose_feedback

            # 判断是否达标
            if compose_feedback.ready:
                if self._ready_since_ts <= 0:
                    self._ready_since_ts = now
                ready_for_gesture = (now - self._ready_since_ts) >= 0.6
            else:
                self._ready_since_ts = 0.0
        elif self._mode_manager.mode == ControlMode.SMART_COMPOSE and selected_template is None:
            # 无模板时也允许手势抓拍
            self._ready_since_ts = 0.0
            ready_for_gesture = True
        else:
            self._ready_since_ts = 0.0
            ready_for_gesture = True

        # 5. 计算跟随命令
        tracking_command = None
        should_auto_move = False

        if (
            self._mode_manager.mode in {ControlMode.AUTO_TRACK, ControlMode.SMART_COMPOSE}
            and stable is not None
            and self._reliable_detection_streak >= RELIABLE_STREAK_FOR_TRACKING
        ):
            should_auto_move = (
                self._mode_manager.mode == ControlMode.AUTO_TRACK
                or compose_auto_control
            )
            if ai_lock_mode_enabled:
                should_auto_move = False

            if should_auto_move and now >= self._tracking_hold_until:
                target_override = (
                    compose_target_override
                    if self._mode_manager.mode == ControlMode.SMART_COMPOSE
                    else None
                )
                tracking_command = self._tracking.compute_command(
                    frame.shape,
                    stable,
                    target_override=target_override,
                )
                if tracking_command is not None:
                    self._tracking_hold_until = now + self._tracking.settle_after_move_s

        # 6. 更新 AI 锁机位 fit score
        if ai_lock_mode_enabled and stable is not None:
            # 这里只更新 runtime_state，实际计算由 AIOrchestrator 负责
            pass

        return ProcessedFrame(
            frame=frame,
            vision=vision,
            stable_detection=stable,
            compose_feedback=compose_feedback,
            compose_target_override=compose_target_override,
            ready_for_gesture=ready_for_gesture,
            should_auto_move=should_auto_move,
            tracking_command=tracking_command,
        )

    def reset_tracking_hold(self) -> None:
        """重置跟随暂停时间（用于手动控制后）"""
        self._tracking_hold_until = time.time() + self._tracking.settle_after_move_s

    @property
    def reliable_detection_streak(self) -> int:
        """获取可靠检测连续帧计数"""
        return self._reliable_detection_streak

    @property
    def ready_since_ts(self) -> float:
        """获取达标开始时间"""
        return self._ready_since_ts
