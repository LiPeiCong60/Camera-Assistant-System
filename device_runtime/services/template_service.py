"""
模板服务模块
负责模板的上传、删除、选择和查询
"""

from __future__ import annotations

import logging
import os
import shutil
import uuid
from dataclasses import replace
from pathlib import Path
from typing import Callable, List, Optional

from device_runtime.repositories.template_repository import TemplateRepository
from device_runtime.services.runtime_state import RuntimeState
from device_runtime.templates.template_compose import TemplateComposeEngine, TemplateProfile
from device_runtime.utils.common_types import BBox, DetectionResult, Point, VisionResult

_TORSO_KEYPOINTS = {11, 12, 23, 24}
_LOWER_BODY_KEYPOINTS = {25, 26, 27, 28}
_LIMB_KEYPOINTS = {13, 14, 15, 16, 25, 26, 27, 28}


class TemplateService:
    """模板服务类，封装所有模板管理逻辑"""

    def __init__(
        self,
        repository: TemplateRepository,
        runtime_state: Optional[RuntimeState] = None,
        detector_factory: Optional[Callable[[], object]] = None,
        storage_dir: str = ".template_library/images",
    ) -> None:
        self._repository = repository
        self._runtime_state = runtime_state
        self._detector_factory = detector_factory or self._build_default_detector
        self._storage_dir = Path(storage_dir)
        self._storage_dir.mkdir(parents=True, exist_ok=True)
        self._logger = logging.getLogger(__name__)
        self._repair_attempted = False
        self._repair_suspicious_templates()

    def import_template(self, image_path: str, name: Optional[str] = None) -> Optional[TemplateProfile]:
        """导入新模板"""
        image = self._read_image(image_path)
        self._logger.info("导入模板: %s, 尺寸: %sx%s", image_path, image.shape[1], image.shape[0])

        detection = self._detect_template_subject(image)
        if detection is None:
            raise ValueError("模板姿势识别失败: 未检测到有效人物姿势")

        if name is None:
            name = os.path.splitext(os.path.basename(image_path))[0]

        stored_image_path = self._persist_template_image(image_path)
        profile = self._build_profile(
            image=image,
            image_path=str(stored_image_path),
            detection=detection,
            name=name,
        )
        self._repository.add(profile)
        return profile

    def delete_template(self, template_id: str) -> bool:
        """删除模板"""
        removed = self._repository.remove(template_id)
        if removed and self._runtime_state is not None and self._runtime_state.selected_template_id == template_id:
            self._runtime_state.selected_template_id = None
        return removed

    def get_template(self, template_id: str) -> Optional[TemplateProfile]:
        """获取模板"""
        return self._repository.get(template_id)

    def list_templates(self) -> List[TemplateProfile]:
        """列出所有模板"""
        self._repair_suspicious_templates()
        return self._repository.list_all()

    def select_template(self, template_id: str) -> bool:
        """选择模板"""
        if not self._repository.exists(template_id):
            return False
        if self._runtime_state is not None:
            self._runtime_state.selected_template_id = template_id
        return True

    def get_selected_template_id(self) -> Optional[str]:
        """获取当前选中的模板ID"""
        if self._runtime_state is None:
            return None
        selected_id = self._runtime_state.selected_template_id
        if selected_id and self._repository.exists(selected_id):
            return selected_id
        return None

    def get_selected_template(self) -> Optional[TemplateProfile]:
        """获取当前选中的模板"""
        selected_id = self.get_selected_template_id()
        if not selected_id:
            return None
        return self._repository.get(selected_id)

    def clear_selected_template(self) -> None:
        """清空当前选中的模板"""
        if self._runtime_state is not None:
            self._runtime_state.selected_template_id = None

    def _persist_template_image(self, image_path: str) -> Path:
        suffix = Path(image_path).suffix or ".jpg"
        target_path = self._storage_dir / f"{uuid.uuid4().hex}{suffix}"
        shutil.copy2(image_path, target_path)
        return target_path

    def _read_image(self, image_path: str):
        import cv2

        image = cv2.imread(image_path)
        if image is None:
            raise ValueError("模板读取失败: 图片无法打开")
        return image

    def _build_profile(
        self,
        *,
        image,
        image_path: str,
        detection: DetectionResult,
        name: str,
        preserve_template_id: str | None = None,
        preserve_created_at: str | None = None,
    ) -> TemplateProfile:
        profile = TemplateComposeEngine.create_profile(name, image_path, detection, image.shape)
        if profile is None:
            raise ValueError("模板姿势识别失败: 未生成有效模板数据")
        if self._profile_needs_repair(profile):
            raise ValueError("模板姿势识别失败: 模板框异常，已拒绝保存")
        if preserve_template_id is not None or preserve_created_at is not None:
            profile = replace(
                profile,
                template_id=preserve_template_id or profile.template_id,
                created_at=preserve_created_at or profile.created_at,
            )
        self._logger.info(
            "模板创建成功: %s, bbox_norm=(%.3f, %.3f, %.3f, %.3f), area_ratio=%.3f, keypoints=%s",
            profile.template_id,
            profile.bbox_norm[0],
            profile.bbox_norm[1],
            profile.bbox_norm[2],
            profile.bbox_norm[3],
            profile.area_ratio,
            len(profile.pose_points_image),
        )
        return profile

    def _detect_template_subject(self, image) -> DetectionResult | None:
        primary_detector = self._detector_factory()
        primary_best = self._best_detection_from_vision(primary_detector.detect(image), image.shape)
        if self._is_usable_template_detection(primary_best, image.shape):
            return primary_best

        fallback = self._detect_with_yolo_crop(image)
        if self._is_usable_template_detection(fallback, image.shape):
            return fallback

        if primary_best is not None:
            guided = self._detect_with_crop_bbox(image, primary_best.bbox, source_label="primary_crop")
            if self._is_usable_template_detection(guided, image.shape):
                return guided

        if primary_best is not None:
            self._logger.warning(
                "模板姿势识别不足: keypoints=%s, bbox=(%s,%s,%s,%s)",
                len(primary_best.pose_landmarks or {}),
                primary_best.bbox.x,
                primary_best.bbox.y,
                primary_best.bbox.w,
                primary_best.bbox.h,
            )
        return None

    def _detect_with_yolo_crop(self, image) -> DetectionResult | None:
        try:
            yolo = self._build_yolo_detector()
        except Exception as exc:
            self._logger.warning("模板导入 YOLO 兜底不可用: %s", exc)
            return None
        if yolo is None:
            return None

        yolo_bbox, yolo_conf = yolo.detect_person_bbox(image)
        if yolo_bbox is None:
            return None

        detection = self._detect_with_crop_bbox(image, yolo_bbox, source_label="yolo_crop")
        if detection is not None:
            detection.confidence = max(float(detection.confidence), float(yolo_conf))
        return detection

    def _detect_with_crop_bbox(
        self,
        image,
        bbox: BBox,
        *,
        source_label: str,
    ) -> DetectionResult | None:
        x1, y1, x2, y2 = self._expand_bbox(bbox, image.shape, padding_ratio=0.18)
        crop = image[y1:y2, x1:x2]
        if crop.size == 0:
            return None

        crop_detector = self._detector_factory()
        crop_best = self._best_detection_from_vision(crop_detector.detect(crop), crop.shape)
        if crop_best is None:
            return None

        pose_landmarks = None
        if crop_best.pose_landmarks:
            pose_landmarks = {
                idx: Point(x=float(p.x) + x1, y=float(p.y) + y1)
                for idx, p in crop_best.pose_landmarks.items()
            }

        anchor_point = crop_best.anchor_point
        if anchor_point is not None:
            anchor_point = Point(x=float(anchor_point.x) + x1, y=float(anchor_point.y) + y1)

        detection = DetectionResult(
            bbox=BBox(
                x=max(0, int(bbox.x)),
                y=max(0, int(bbox.y)),
                w=max(2, int(bbox.w)),
                h=max(2, int(bbox.h)),
            ),
            confidence=float(crop_best.confidence),
            label=f"template_pose_{source_label}",
            anchor_point=anchor_point,
            pose_landmarks=pose_landmarks,
        )
        if self._is_usable_template_detection(detection, image.shape):
            self._logger.info(
                "模板导入使用裁剪兜底(%s): bbox=(%s,%s,%s,%s), keypoints=%s",
                source_label,
                detection.bbox.x,
                detection.bbox.y,
                detection.bbox.w,
                detection.bbox.h,
                len(detection.pose_landmarks or {}),
            )
        return detection

    def _best_detection_from_vision(
        self,
        vision: VisionResult,
        frame_shape: tuple[int, int, int],
    ) -> DetectionResult | None:
        candidates = list(vision.tracking_candidates or [])
        if vision.tracking_detection is not None:
            candidates.append(vision.tracking_detection)
        if not candidates:
            return None
        return max(candidates, key=lambda det: self._score_detection(det, frame_shape))

    def _score_detection(self, detection: DetectionResult, frame_shape: tuple[int, int, int]) -> float:
        if detection is None:
            return float("-inf")
        h, w = frame_shape[:2]
        pose_landmarks = detection.pose_landmarks or {}
        area_ratio = detection.bbox.area / float(max(1, w * h))
        keypoint_count = len(pose_landmarks)
        torso_count = sum(1 for idx in _TORSO_KEYPOINTS if idx in pose_landmarks)
        lower_count = sum(1 for idx in _LOWER_BODY_KEYPOINTS if idx in pose_landmarks)
        limb_count = sum(1 for idx in _LIMB_KEYPOINTS if idx in pose_landmarks)
        area_score = max(0.0, 1.0 - abs(area_ratio - 0.28) / 0.28)
        center = detection.anchor_point if detection.anchor_point is not None else detection.bbox.center
        dx = (float(center.x) / float(max(1, w))) - 0.5
        dy = (float(center.y) / float(max(1, h))) - 0.5
        center_score = max(0.0, 1.0 - ((dx * dx + dy * dy) ** 0.5) / 0.75)
        return (
            keypoint_count * 14.0
            + torso_count * 22.0
            + lower_count * 12.0
            + limb_count * 4.0
            + float(detection.confidence) * 18.0
            + area_score * 14.0
            + center_score * 8.0
        )

    def _is_usable_template_detection(
        self,
        detection: DetectionResult | None,
        frame_shape: tuple[int, int, int],
    ) -> bool:
        if detection is None:
            return False
        h, w = frame_shape[:2]
        pose_landmarks = detection.pose_landmarks or {}
        if not pose_landmarks:
            return False
        keypoint_count = len(pose_landmarks)
        torso_count = sum(1 for idx in _TORSO_KEYPOINTS if idx in pose_landmarks)
        lower_count = sum(1 for idx in _LOWER_BODY_KEYPOINTS if idx in pose_landmarks)
        area_ratio = detection.bbox.area / float(max(1, w * h))
        if area_ratio <= 0.03 or area_ratio >= 0.92:
            return False
        if detection.bbox.w < max(24, int(w * 0.08)) or detection.bbox.h < max(48, int(h * 0.16)):
            return False
        if torso_count < 3:
            return False
        if keypoint_count >= 8:
            return True
        return keypoint_count >= 6 and lower_count >= 2

    def _repair_suspicious_templates(self) -> None:
        if self._repair_attempted:
            return
        self._repair_attempted = True

        templates = list(self._repository.list_all())
        repaired_count = 0
        for profile in templates:
            if not self._profile_needs_repair(profile):
                continue
            image_path = profile.image_path
            if not image_path or not os.path.exists(image_path):
                self._logger.warning("跳过模板修复，原图不存在: %s", image_path)
                continue
            try:
                image = self._read_image(image_path)
                detection = self._detect_template_subject(image)
                if detection is None:
                    raise ValueError("未检测到可用姿势")
                repaired = self._build_profile(
                    image=image,
                    image_path=image_path,
                    detection=detection,
                    name=profile.name,
                    preserve_template_id=profile.template_id,
                    preserve_created_at=profile.created_at,
                )
                self._repository.add(repaired)
                repaired_count += 1
            except Exception as exc:
                self._logger.warning("模板自动修复失败: %s (%s)", profile.template_id, exc)
        if repaired_count:
            self._logger.info("模板自动修复完成: %s 个模板已更新", repaired_count)

    @staticmethod
    def _profile_needs_repair(profile: TemplateProfile) -> bool:
        bbox_norm = profile.bbox_norm or (0.0, 0.0, 0.0, 0.0)
        full_image_bbox = (
            bbox_norm[0] <= 0.02
            and bbox_norm[1] <= 0.02
            and bbox_norm[2] >= 0.98
            and bbox_norm[3] >= 0.98
        )
        area_is_full = float(profile.area_ratio) >= 0.95
        bbox_points = profile.pose_points_bbox or {}
        image_points = profile.pose_points_image or {}
        identical_points = False
        common = set(bbox_points).intersection(image_points)
        if len(common) >= 3:
            identical_points = all(
                abs(float(bbox_points[idx][0]) - float(image_points[idx][0])) <= 0.015
                and abs(float(bbox_points[idx][1]) - float(image_points[idx][1])) <= 0.015
                for idx in common
            )
        return full_image_bbox or area_is_full or identical_points

    @staticmethod
    def _expand_bbox(
        bbox: BBox,
        frame_shape: tuple[int, int, int],
        *,
        padding_ratio: float,
    ) -> tuple[int, int, int, int]:
        h, w = frame_shape[:2]
        pad_x = int(max(12.0, bbox.w * padding_ratio))
        pad_y = int(max(16.0, bbox.h * padding_ratio))
        x1 = max(0, int(bbox.x - pad_x))
        y1 = max(0, int(bbox.y - pad_y))
        x2 = min(w, int(bbox.x + bbox.w + pad_x))
        y2 = min(h, int(bbox.y + bbox.h + pad_y))
        return x1, y1, x2, y2

    @staticmethod
    def _build_default_detector():
        from device_runtime.config import DetectionConfig
        from device_runtime.vision.detector import MediaPipeVisionDetector

        cfg = DetectionConfig()
        cfg.min_confidence = 0.25
        cfg.max_inference_side = 1280
        cfg.enable_face_landmarks = False
        cfg.yolo_every_n_frames = 1
        return MediaPipeVisionDetector(cfg)

    @staticmethod
    def _build_yolo_detector():
        from device_runtime.vision.detector import YoloPersonDetector

        return YoloPersonDetector(model_path="yolo11n.pt", conf=0.25, device="cpu")
