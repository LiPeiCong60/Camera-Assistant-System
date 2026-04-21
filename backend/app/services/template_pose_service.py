"""Helpers for creating template data from an uploaded reference photo."""

from __future__ import annotations

from dataclasses import asdict
from functools import lru_cache
from pathlib import Path
from urllib.parse import unquote, urlparse

import cv2
from fastapi import HTTPException, status

from backend.app.core.config import get_settings
from device_runtime.config import DetectionConfig
from device_runtime.templates.template_compose import TemplateComposeEngine
from device_runtime.vision.detector import MediaPipeVisionDetector


@lru_cache(maxsize=1)
def _build_detector() -> MediaPipeVisionDetector:
    config = DetectionConfig(
        min_confidence=0.25,
        max_inference_side=1280,
        enable_face_landmarks=False,
        yolo_every_n_frames=1,
    )
    return MediaPipeVisionDetector(config)


class TemplatePoseService:
    """Generate structured template data from an uploaded photo."""

    def create_template_data(self, *, name: str, source_image_url: str) -> dict[str, object]:
        image_path = self._resolve_source_image_path(source_image_url)
        frame = cv2.imread(str(image_path))
        if frame is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="template source image could not be read",
            )

        vision_result = _build_detector().detect(frame)
        detection = vision_result.tracking_detection
        if detection is None and vision_result.tracking_candidates:
            detection = vision_result.tracking_candidates[0]
        if detection is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="no pose detected in template source image",
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
                detail="failed to build template data from source image",
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
