"""Helpers for creating template data from an uploaded reference photo."""

from __future__ import annotations

from dataclasses import asdict
from functools import lru_cache
from pathlib import Path
from urllib.parse import unquote, urlparse

import cv2
import numpy as np
from fastapi import HTTPException, status
from PIL import Image, ImageOps

from backend.app.core.config import get_settings
from device_runtime.config import DetectionConfig
from device_runtime.templates.template_compose import TemplateComposeEngine
from device_runtime.vision.detector import MediaPipeVisionDetector


@lru_cache(maxsize=4)
def _build_detector(
    min_confidence: float = 0.25,
    max_inference_side: int = 1280,
) -> MediaPipeVisionDetector:
    config = DetectionConfig(
        min_confidence=min_confidence,
        max_inference_side=max_inference_side,
        enable_face_landmarks=False,
        yolo_every_n_frames=1,
    )
    return MediaPipeVisionDetector(config)


_DETECTION_CONFIGS = (
    (0.25, 1280),
    (0.18, 1600),
    (0.12, 1920),
)


def _read_image_with_orientation(image_path: Path) -> np.ndarray | None:
    try:
        image = ImageOps.exif_transpose(Image.open(image_path)).convert("RGB")
        return cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
    except Exception:
        return cv2.imread(str(image_path))


def _detect_template_pose(frame: np.ndarray):
    for min_confidence, max_inference_side in _DETECTION_CONFIGS:
        vision_result = _build_detector(min_confidence, max_inference_side).detect(frame)
        detection = vision_result.tracking_detection
        if detection is None and vision_result.tracking_candidates:
            detection = vision_result.tracking_candidates[0]
        if detection is not None:
            return detection
    return None


class TemplatePoseService:
    """Generate structured template data from an uploaded photo."""

    def create_template_data(self, *, name: str, source_image_url: str) -> dict[str, object]:
        image_path = self._resolve_source_image_path(source_image_url)
        frame = _read_image_with_orientation(image_path)
        if frame is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="template source image could not be read",
            )

        detection = _detect_template_pose(frame)
        if detection is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "未识别到人体姿态，请换一张人物主体更完整、更清晰、"
                    "遮挡更少的模板照片，或在手机端选择“本地识别”。"
                ),
            )

        profile = TemplateComposeEngine.create_profile(
            name=name,
            image_path=str(image_path),
            detection=detection,
            frame_shape=frame.shape,
        )
        if profile is None or not profile.pose_points_image:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="模板人体关键点不足，请换一张人物更完整、更清晰的模板照片。",
            )

        payload = asdict(profile)
        payload["pose_points"] = {
            str(key): [float(value[0]), float(value[1])]
            for key, value in profile.pose_points.items()
        }
        payload["pose_points_image"] = {
            str(key): [float(value[0]), float(value[1])]
            for key, value in profile.pose_points_image.items()
        }
        payload["pose_points_bbox"] = {
            str(key): [float(value[0]), float(value[1])]
            for key, value in profile.pose_points_bbox.items()
        }
        payload["bbox_norm"] = [float(item) for item in profile.bbox_norm]
        head_bbox_norm = _build_head_bbox_norm(payload)
        if head_bbox_norm is not None:
            payload["head_bbox_norm"] = head_bbox_norm
        return payload

    def _resolve_source_image_path(self, source_image_url: str) -> Path:
        raw = source_image_url.strip()
        if not raw:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="template source image is required",
            )

        direct_path = Path(raw)
        if direct_path.exists():
            return direct_path.resolve()

        settings = get_settings()
        uploads_root = Path(settings.uploads_dir).resolve()
        parsed = urlparse(raw)
        path_value = unquote(parsed.path or raw)
        uploads_prefix = settings.uploads_url_path.rstrip("/")
        if uploads_prefix and path_value.startswith(uploads_prefix):
            relative_path = path_value[len(uploads_prefix) :].lstrip("/\\")
            resolved_path = (uploads_root / relative_path).resolve()
            if uploads_root in resolved_path.parents or resolved_path == uploads_root:
                if resolved_path.exists():
                    return resolved_path

        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="template source image path could not be resolved",
        )


def _build_head_bbox_norm(payload: dict[str, object]) -> list[float] | None:
    explicit = payload.get("head_bbox_norm")
    if isinstance(explicit, list) and len(explicit) == 4:
        return [float(item) for item in explicit]

    pose_points = payload.get("pose_points_image")
    if isinstance(pose_points, dict):
        points: list[tuple[float, float]] = []
        for index in ("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"):
            value = pose_points.get(index)
            if isinstance(value, list) and len(value) >= 2:
                points.append((_clamp01(float(value[0])), _clamp01(float(value[1]))))
        if points:
            return _expanded_box_from_points(points, min_width=0.10, min_height=0.10)

    anchor_x = _coerce_float(payload.get("head_anchor_norm_x")) or _coerce_float(
        payload.get("face_anchor_norm_x")
    )
    anchor_y = _coerce_float(payload.get("head_anchor_norm_y")) or _coerce_float(
        payload.get("face_anchor_norm_y")
    )
    bbox = payload.get("bbox_norm")
    if isinstance(bbox, list) and len(bbox) == 4:
        body_w = _clamp01(float(bbox[2]))
        body_h = _clamp01(float(bbox[3]))
        if anchor_x is not None and anchor_y is not None:
            width = _clamp(body_w * 0.42 if body_w > 0 else 0.18, 0.10, 0.24)
            height = _clamp(width * 1.12, 0.11, 0.26)
            return _box_around_point(anchor_x, anchor_y, width, height)
        if body_w > 0 and body_h > 0:
            left = _clamp01(float(bbox[0]))
            top = _clamp01(float(bbox[1]))
            width = _clamp(body_w * 0.38, 0.10, 0.24)
            height = _clamp(body_h * 0.17, 0.11, 0.26)
            return [
                _clamp01(left + (body_w - width) * 0.5),
                _clamp01(top + body_h * 0.02),
                _clamp_dimension(width, left + (body_w - width) * 0.5),
                _clamp_dimension(height, top + body_h * 0.02),
            ]

    return None


def _expanded_box_from_points(
    points: list[tuple[float, float]],
    *,
    min_width: float,
    min_height: float,
) -> list[float]:
    min_x = min(point[0] for point in points)
    max_x = max(point[0] for point in points)
    min_y = min(point[1] for point in points)
    max_y = max(point[1] for point in points)
    width = _clamp((max_x - min_x) * 1.9, min_width, 0.26)
    height = _clamp((max_y - min_y) * 2.2, min_height, 0.28)
    return _box_around_point((min_x + max_x) * 0.5, (min_y + max_y) * 0.5, width, height)


def _box_around_point(x: float, y: float, width: float, height: float) -> list[float]:
    left = _clamp01(x - width * 0.5)
    top = _clamp01(y - height * 0.5)
    return [
        left,
        top,
        _clamp_dimension(width, left),
        _clamp_dimension(height, top),
    ]


def _coerce_float(value: object) -> float | None:
    if value is None:
        return None
    try:
        return _clamp01(float(value))
    except (TypeError, ValueError):
        return None


def _clamp01(value: float) -> float:
    return _clamp(value, 0.0, 1.0)


def _clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def _clamp_dimension(value: float, start: float) -> float:
    return _clamp(value, 0.0, 1.0 - _clamp01(start))
