from __future__ import annotations

from device_runtime.mode_manager import ControlMode

MODE_TEXT = {
    ControlMode.MANUAL: "手动",
    ControlMode.AUTO_TRACK: "自动跟随",
    ControlMode.SMART_COMPOSE: "模板引导",
}

FOLLOW_TEXT = {
    "shoulders": "肩部",
    "face": "面部",
}

FOLLOW_MODE_ALIASES = {
    "shoulders": "shoulders",
    "shoulder": "shoulders",
    "shoulder_center": "shoulders",
    "face": "face",
    "face_center": "face",
}

FOLLOW_MODE_TARGET_TYPES = {
    "shoulders": "shoulder_center",
    "face": "face_center",
}

SPEED_TEXT = {
    "slow": "慢速",
    "normal": "标准",
    "fast": "快速",
    "turbo": "灵敏",
}

DETECTION_LABEL_TEXT = {
    "person_pose": "人体(姿态)",
    "person_mp_yolo": "人体(融合)",
    "face_center": "面部中心",
    "person": "人体",
}

FOLLOW_TEXT_TO_KEY = {v: k for k, v in FOLLOW_TEXT.items()}
SPEED_TEXT_TO_KEY = {v: k for k, v in SPEED_TEXT.items()}


def mode_to_text(mode: ControlMode) -> str:
    return MODE_TEXT.get(mode, mode.value)


def follow_to_text(mode: str) -> str:
    return FOLLOW_TEXT.get(mode, mode)


def normalize_follow_mode(mode: str) -> str:
    normalized = str(mode).strip().lower()
    return FOLLOW_MODE_ALIASES.get(normalized, normalized)


def follow_mode_to_target_type(mode: str) -> str:
    normalized = normalize_follow_mode(mode)
    return FOLLOW_MODE_TARGET_TYPES.get(normalized, normalized)


def speed_to_text(mode: str) -> str:
    return SPEED_TEXT.get(mode, mode)


def detection_label_to_text(label: str) -> str:
    return DETECTION_LABEL_TEXT.get(label, label)
