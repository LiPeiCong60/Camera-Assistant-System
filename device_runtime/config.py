from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal


@dataclass(slots=True)
class VideoSourceConfig:
    stream_url: str
    reconnect_interval_s: float = 2.0
    threaded_capture: bool = True
    read_sleep_s: float = 0.001
    capture_buffer_size: int = 1


@dataclass(slots=True)
class DetectionConfig:
    min_confidence: float = 0.4
    detector_fps: float = 12.0
    max_inference_side: int = 960
    yolo_every_n_frames: int = 2
    yolo_bbox_smooth_alpha: float = 0.4
    enable_face_landmarks: bool = True
    async_skip_frames: int = 0  # 智能跳帧：0=禁用，1=每2帧检测1次，2=每3帧检测1次


@dataclass(slots=True)
class ServoAxisConfig:
    min_angle: float
    max_angle: float
    home_angle: float
    servo_id: int = 0
    max_step_deg: float = 3.0


ServoDriverKind = Literal["mock", "ttl_bus"]


@dataclass(slots=True)
class TTLBusServoConfig:
    port: str = "/dev/ttyUSB0"
    baudrate: int = 115200
    move_time_ms: int = 120
    timeout_s: float = 0.2


@dataclass(slots=True)
class GimbalConfig:
    pan: ServoAxisConfig
    tilt: ServoAxisConfig
    driver_kind: ServoDriverKind = "ttl_bus"
    ttl_bus: TTLBusServoConfig = field(default_factory=TTLBusServoConfig)
    smooth_sleep_s: float = 0.01
    feedback_poll_interval_s: float = 0.05


@dataclass(slots=True)
class TrackingConfig:
    deadzone_px: int = 30
    debounce_frames: int = 2
    gain_x: float = 0.024
    gain_y: float = 0.024
    max_delta_deg: float = 2.8
    min_command_interval_s: float = 0.08
    command_smooth_alpha: float = 0.4
    min_output_deg: float = 0.1
    max_anchor_jump_px: float = 120.0
    settle_after_move_s: float = 0.18
    invert_pan: bool = False
    invert_tilt: bool = False


@dataclass(slots=True)
class AppConfig:
    manual_step_deg: float = 3.0
    ui_refresh_fps: float = 30.0
    preview_scale: float = 1.0
    enable_overlay: bool = True
    show_body_skeleton: bool = True
    show_face_mesh: bool = True


@dataclass(slots=True)
class SystemConfig:
    video: VideoSourceConfig
    detection: DetectionConfig = field(default_factory=DetectionConfig)
    gimbal: GimbalConfig = field(
        default_factory=lambda: GimbalConfig(
            pan=ServoAxisConfig(min_angle=-135.0, max_angle=135.0, home_angle=0.0, servo_id=0),
            tilt=ServoAxisConfig(min_angle=-90.0, max_angle=130.0, home_angle=15.0, servo_id=1),
        )
    )
    tracking: TrackingConfig = field(default_factory=TrackingConfig)
    app: AppConfig = field(default_factory=AppConfig)


def default_config(stream_url: str) -> SystemConfig:
    return SystemConfig(video=VideoSourceConfig(stream_url=stream_url))


# ============================================================================
# 树莓派运行 Profile
# ============================================================================

RpiMode = Literal["performance", "balanced", "quality"]


@dataclass(slots=True)
class RaspberryPiProfile:
    """
    树莓派运行配置

    三档模式：
    - performance: 性能优先，适合长时间运行，CPU 占用最低
    - balanced: 平衡模式，性能与效果兼顾（默认）
    - quality: 效果优先，适合短时间演示，CPU 占用较高
    """
    mode: RpiMode = "balanced"

    # 检测配置
    detector_fps: float = 8.0
    max_inference_side: int = 640
    yolo_every_n_frames: int = 3
    enable_face_landmarks: bool = False
    async_skip_frames: int = 0  # 智能跳帧

    # 预览配置
    preview_fps: float = 20.0
    preview_scale: float = 0.6

    # 显示配置
    enable_overlay: bool = True
    show_face_mesh: bool = False
    show_body_skeleton: bool = True

    # AI 任务节流
    ai_task_throttle_s: float = 2.0

    @staticmethod
    def performance() -> RaspberryPiProfile:
        """性能优先模式：最低 CPU 占用，适合长时间运行"""
        return RaspberryPiProfile(
            mode="performance",
            detector_fps=6.0,
            max_inference_side=480,
            yolo_every_n_frames=4,
            enable_face_landmarks=False,
            async_skip_frames=1,  # 每2帧检测1次
            preview_fps=15.0,
            preview_scale=0.5,
            enable_overlay=True,
            show_face_mesh=False,
            show_body_skeleton=True,
            ai_task_throttle_s=3.0,
        )

    @staticmethod
    def balanced() -> RaspberryPiProfile:
        """平衡模式：性能与效果兼顾（默认）"""
        return RaspberryPiProfile(
            mode="balanced",
            detector_fps=8.0,
            max_inference_side=640,
            yolo_every_n_frames=3,
            enable_face_landmarks=False,
            async_skip_frames=0,  # 不跳帧
            preview_fps=20.0,
            preview_scale=0.6,
            enable_overlay=True,
            show_face_mesh=False,
            show_body_skeleton=True,
            ai_task_throttle_s=2.0,
        )

    @staticmethod
    def quality() -> RaspberryPiProfile:
        """效果优先模式：适合短时间演示"""
        return RaspberryPiProfile(
            mode="quality",
            detector_fps=10.0,
            max_inference_side=800,
            yolo_every_n_frames=2,
            enable_face_landmarks=True,
            async_skip_frames=0,  # 不跳帧
            preview_fps=25.0,
            preview_scale=0.8,
            enable_overlay=True,
            show_face_mesh=False,
            show_body_skeleton=True,
            ai_task_throttle_s=1.5,
        )


def apply_rpi_profile(cfg: SystemConfig, profile: RaspberryPiProfile) -> None:
    """
    应用树莓派 Profile 到系统配置

    这会修改传入的 cfg 对象
    """
    cfg.detection.detector_fps = profile.detector_fps
    cfg.detection.max_inference_side = profile.max_inference_side
    cfg.detection.yolo_every_n_frames = profile.yolo_every_n_frames
    cfg.detection.async_skip_frames = profile.async_skip_frames
    cfg.detection.enable_face_landmarks = profile.enable_face_landmarks

    cfg.app.ui_refresh_fps = profile.preview_fps
    cfg.app.preview_scale = profile.preview_scale
    cfg.app.enable_overlay = profile.enable_overlay
    cfg.app.show_face_mesh = profile.show_face_mesh
    cfg.app.show_body_skeleton = profile.show_body_skeleton

