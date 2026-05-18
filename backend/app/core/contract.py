"""Helpers for the first-phase cross-client data contract."""

from __future__ import annotations

from typing import Any


CANONICAL_CAPTURE_SESSION_MODES = frozenset(
    {
        "mobile_only",
        "gimbal_manual",
        "gimbal_follow",
        "gimbal_template",
        "ai_auto_angle",
        "ai_background",
    }
)
LEGACY_CAPTURE_SESSION_MODE_MAP = {
    "device_link": "gimbal_manual",
    "MANUAL": "gimbal_manual",
    "AUTO_TRACK": "gimbal_follow",
    "SMART_COMPOSE": "gimbal_template",
}

CANONICAL_AI_TASK_TYPES = frozenset(
    {
        "analyze_photo",
        "analyze_background",
        "batch_pick",
        "auto_angle",
        "template_match",
        "video_analysis",
    }
)
LEGACY_AI_TASK_TYPE_MAP = {
    "background_lock": "analyze_background",
    "analyze_template": "template_match",
}

CANONICAL_CAPTURE_TYPES = frozenset(
    {
        "single",
        "burst",
        "best",
        "background",
        "template",
        "recording",
    }
)
LEGACY_CAPTURE_TYPE_MAP = {
    "photo": "single",
    "device_link": "single",
}
CANONICAL_MEDIA_TYPES = frozenset({"photo", "video"})

DEFAULT_TARGET_BOX_LABEL = "recommended_person_position"
DEFAULT_TARGET_BOX_NORM = {
    "x": 0.38,
    "y": 0.18,
    "w": 0.24,
    "h": 0.66,
    "label": DEFAULT_TARGET_BOX_LABEL,
}


def normalize_capture_session_mode(value: Any, *, default: str = "mobile_only") -> str:
    raw = _clean_text(value, default=default)
    return LEGACY_CAPTURE_SESSION_MODE_MAP.get(raw, LEGACY_CAPTURE_SESSION_MODE_MAP.get(raw.upper(), raw))


def normalize_ai_task_type(value: Any, *, default: str = "analyze_photo") -> str:
    raw = _clean_text(value, default=default)
    return LEGACY_AI_TASK_TYPE_MAP.get(raw, LEGACY_AI_TASK_TYPE_MAP.get(raw.lower(), raw))


def normalize_capture_type(value: Any, *, default: str = "single") -> str:
    raw = _clean_text(value, default=default)
    return LEGACY_CAPTURE_TYPE_MAP.get(raw, LEGACY_CAPTURE_TYPE_MAP.get(raw.lower(), raw))


def is_capture_session_mode(value: str) -> bool:
    return value in CANONICAL_CAPTURE_SESSION_MODES


def is_ai_task_type(value: str) -> bool:
    return value in CANONICAL_AI_TASK_TYPES


def is_capture_type(value: str) -> bool:
    return value in CANONICAL_CAPTURE_TYPES


def normalize_capture_metadata(
    metadata: Any,
    *,
    capture_type: Any = None,
    media_type: Any = None,
    duration_ms: Any = None,
    local_album_saved: Any = None,
) -> dict[str, Any]:
    data = dict(metadata) if isinstance(metadata, dict) else {}
    normalized_capture_type = normalize_capture_type(capture_type)
    default_media_type = _default_media_type_for_capture(normalized_capture_type)

    if _clean_text(capture_type).lower() == "device_link":
        data.setdefault("source", "device_link")

    if media_type is not None:
        data["media_type"] = normalize_media_type(media_type, default=default_media_type)
    else:
        data["media_type"] = normalize_media_type(data.get("media_type"), default=default_media_type)

    if duration_ms is not None:
        data["duration_ms"] = _coerce_non_negative_int(duration_ms)
    elif "duration_ms" in data:
        data["duration_ms"] = _coerce_non_negative_int(data.get("duration_ms"))

    if local_album_saved is not None:
        data["local_album_saved"] = _coerce_bool(local_album_saved)
    elif "local_album_saved" in data:
        data["local_album_saved"] = _coerce_bool(data.get("local_album_saved"))
    elif "album_saved" in data:
        data["local_album_saved"] = _coerce_bool(data.get("album_saved"))
    else:
        data["local_album_saved"] = False

    return data


def extract_capture_media_fields(metadata: Any, *, capture_type: Any = None) -> dict[str, Any]:
    data = metadata if isinstance(metadata, dict) else {}
    normalized_capture_type = normalize_capture_type(capture_type)
    default_media_type = _default_media_type_for_capture(normalized_capture_type)
    local_album_saved = data.get("local_album_saved", data.get("album_saved", False))
    return {
        "media_type": normalize_media_type(data.get("media_type"), default=default_media_type),
        "duration_ms": _coerce_non_negative_int(data.get("duration_ms")),
        "local_album_saved": _coerce_bool(local_album_saved),
    }


def normalize_media_type(value: Any, *, default: str = "photo") -> str:
    raw = _clean_text(value).lower()
    return raw if raw in CANONICAL_MEDIA_TYPES else default


def normalize_target_box_norm(
    value: Any,
    *,
    default: dict[str, Any] | None = None,
    label: str = DEFAULT_TARGET_BOX_LABEL,
) -> dict[str, Any] | None:
    if value is None:
        return dict(default) if default is not None else None

    raw_label = label
    if isinstance(value, dict):
        raw_values = (value.get("x"), value.get("y"), value.get("w"), value.get("h"))
        raw_label = _clean_text(value.get("label"), default=label)
    elif isinstance(value, (list, tuple)) and len(value) >= 4:
        raw_values = (value[0], value[1], value[2], value[3])
    else:
        return dict(default) if default is not None else None

    try:
        x, y, w, h = [_clamp01(float(item)) for item in raw_values]
    except (TypeError, ValueError):
        return dict(default) if default is not None else None

    if x + w > 1.0:
        x = max(0.0, 1.0 - w)
    if y + h > 1.0:
        y = max(0.0, 1.0 - h)

    return {
        "x": round(x, 4),
        "y": round(y, 4),
        "w": round(w, 4),
        "h": round(h, 4),
        "label": raw_label,
    }


def normalize_ai_response_payload(payload: Any) -> dict[str, Any] | None:
    if not isinstance(payload, dict):
        return None

    normalized = dict(payload)
    if "task_type" in normalized:
        normalized["task_type"] = normalize_ai_task_type(normalized.get("task_type"))

    if "target_box_norm" in normalized:
        target_box_norm = normalize_target_box_norm(normalized.get("target_box_norm"))
        normalized["target_box_norm"] = target_box_norm

    return normalized


def _clean_text(value: Any, *, default: str = "") -> str:
    if value is None:
        return default
    text = str(value).strip()
    return text or default


def _default_media_type_for_capture(capture_type: str) -> str:
    return "video" if capture_type == "recording" else "photo"


def _coerce_non_negative_int(value: Any) -> int | None:
    if value is None or value == "":
        return None
    try:
        result = int(float(value))
    except (TypeError, ValueError):
        return None
    return max(0, result)


def _coerce_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"true", "1", "yes", "y", "on"}:
            return True
        if normalized in {"false", "0", "no", "n", "off", ""}:
            return False
    return bool(value)


def _clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))
