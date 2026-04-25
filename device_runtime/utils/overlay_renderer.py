from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from device_runtime.app_core import TEMPLATE_CORE_EDGES
from device_runtime.templates.template_compose import TemplateProfile, project_template_pose_points
from device_runtime.utils.common_types import VisionResult


HAND_EDGES: tuple[tuple[int, int], ...] = (
    (0, 1), (1, 2), (2, 3), (3, 4),
    (0, 5), (5, 6), (6, 7), (7, 8),
    (5, 9), (9, 10), (10, 11), (11, 12),
    (9, 13), (13, 14), (14, 15), (15, 16),
    (13, 17), (17, 18), (18, 19), (19, 20),
    (0, 17),
)


@dataclass(slots=True)
class OverlaySettings:
    enabled: bool = True
    show_live_person_bbox: bool = True
    show_live_body_skeleton: bool = True
    show_live_hands: bool = True
    show_template_bbox: bool = True
    show_template_skeleton: bool = True
    show_ai_lock_box: bool = True

    def as_dict(self) -> dict[str, bool]:
        return {
            "enabled": self.enabled,
            "show_live_person_bbox": self.show_live_person_bbox,
            "show_live_body_skeleton": self.show_live_body_skeleton,
            "show_live_hands": self.show_live_hands,
            "show_template_bbox": self.show_template_bbox,
            "show_template_skeleton": self.show_template_skeleton,
            "show_ai_lock_box": self.show_ai_lock_box,
        }

    def update_from_dict(self, values: dict[str, object]) -> None:
        for key in self.as_dict():
            if key in values and values[key] is not None:
                setattr(self, key, bool(values[key]))


class DeviceOverlayRenderer:
    def draw(
        self,
        frame: np.ndarray,
        *,
        vision: VisionResult | None,
        selected_template: TemplateProfile | None,
        settings: OverlaySettings,
        ai_lock_target_box_norm: tuple[float, float, float, float] | None = None,
    ) -> None:
        if not settings.enabled:
            return
        if vision is not None:
            self._draw_live_overlay(frame, vision, settings)
        if selected_template is not None:
            self._draw_template_overlay(frame, selected_template, settings)
        if settings.show_ai_lock_box and ai_lock_target_box_norm is not None:
            self._draw_norm_box(frame, ai_lock_target_box_norm, (80, 220, 255), "AI lock")

    def _draw_live_overlay(
        self,
        frame: np.ndarray,
        vision: VisionResult,
        settings: OverlaySettings,
    ) -> None:
        if settings.show_live_body_skeleton:
            for seg in vision.body_skeleton or []:
                cv2.line(
                    frame,
                    (int(seg.start.x), int(seg.start.y)),
                    (int(seg.end.x), int(seg.end.y)),
                    (50, 220, 255),
                    2,
                )

        if settings.show_live_hands:
            for hand in vision.hand_landmarks or []:
                if len(hand) < 21:
                    continue
                for start, end in HAND_EDGES:
                    cv2.line(
                        frame,
                        (int(hand[start].x), int(hand[start].y)),
                        (int(hand[end].x), int(hand[end].y)),
                        (240, 110, 30),
                        2,
                    )
                for point in hand:
                    cv2.circle(frame, (int(point.x), int(point.y)), 2, (60, 240, 255), -1)

        if settings.show_live_person_bbox and vision.person_bbox is not None:
            bbox = vision.person_bbox
            cv2.rectangle(
                frame,
                (bbox.x, bbox.y),
                (bbox.x + bbox.w, bbox.y + bbox.h),
                (0, 220, 0),
                2,
            )
            cv2.putText(
                frame,
                "person",
                (bbox.x, max(16, bbox.y - 6)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (0, 220, 0),
                1,
            )

    def _draw_template_overlay(
        self,
        frame: np.ndarray,
        selected_template: TemplateProfile,
        settings: OverlaySettings,
    ) -> None:
        color = (230, 120, 255)
        if settings.show_template_skeleton:
            projected = project_template_pose_points(selected_template, frame.shape, mirror_view=False)
            for start, end in TEMPLATE_CORE_EDGES:
                p1 = projected.get(start)
                p2 = projected.get(end)
                if p1 is not None and p2 is not None:
                    cv2.line(frame, p1, p2, color, 2)
            for point in projected.values():
                cv2.circle(frame, point, 3, color, -1)

        if settings.show_template_bbox:
            self._draw_norm_box(frame, selected_template.bbox_norm, color, "template")

    def _draw_norm_box(
        self,
        frame: np.ndarray,
        bbox_norm: tuple[float, float, float, float],
        color: tuple[int, int, int],
        label: str,
    ) -> None:
        if len(bbox_norm) != 4:
            return
        x_norm, y_norm, w_norm, h_norm = bbox_norm
        if w_norm <= 0.0 or h_norm <= 0.0:
            return
        height, width = frame.shape[:2]
        x = int(max(0, min(width - 1, x_norm * width)))
        y = int(max(0, min(height - 1, y_norm * height)))
        w = int(max(1, min(width - x, w_norm * width)))
        h = int(max(1, min(height - y, h_norm * height)))
        cv2.rectangle(frame, (x, y), (x + w, y + h), color, 2)
        cv2.putText(
            frame,
            label,
            (x, max(16, y - 6)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            color,
            1,
        )
