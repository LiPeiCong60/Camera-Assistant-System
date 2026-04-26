from __future__ import annotations

import unittest

import cv2
import numpy as np

from device_runtime.api.app import app
from device_runtime.api.routes.status import DeviceRuntimeConfigRequest
from device_runtime.api.session_manager import DeviceSessionContext
from device_runtime.config import RaspberryPiProfile, apply_rpi_profile, default_config
from device_runtime.services.runtime_state import RuntimeState
from device_runtime.templates.template_compose import GestureCaptureState, TemplateProfile
from device_runtime.utils.common_types import BBox, DetectionResult, LineSegment, Point, VisionResult
from device_runtime.utils.overlay_renderer import DeviceOverlayRenderer, OverlaySettings


def _template_profile() -> TemplateProfile:
    return TemplateProfile(
        template_id="template-1",
        name="Template",
        image_path="",
        created_at="now",
        anchor_norm_x=0.5,
        anchor_norm_y=0.5,
        shoulder_anchor_norm_x=0.5,
        shoulder_anchor_norm_y=0.5,
        head_anchor_norm_x=None,
        head_anchor_norm_y=None,
        face_anchor_norm_x=None,
        face_anchor_norm_y=None,
        area_ratio=0.2,
        facing_sign=0.0,
        pose_points={},
        pose_points_image={
            11: (0.4, 0.3),
            12: (0.6, 0.3),
            23: (0.43, 0.7),
            24: (0.57, 0.7),
        },
        pose_points_bbox={
            11: (0.25, 0.2),
            12: (0.75, 0.2),
            23: (0.35, 0.7),
            24: (0.65, 0.7),
        },
        bbox_norm=(0.3, 0.2, 0.35, 0.6),
    )


def _open_hand() -> list[Point]:
    hand = [Point(0, 0) for _ in range(21)]
    for tip, pip in zip([4, 8, 12, 16, 20], [3, 6, 10, 14, 18]):
        hand[pip] = Point(10, pip)
        hand[tip] = Point(30, tip)
    return hand


def _fist_hand() -> list[Point]:
    hand = [Point(0, 0) for _ in range(21)]
    for tip, pip in zip([4, 8, 12, 16, 20], [3, 6, 10, 14, 18]):
        hand[pip] = Point(12, pip)
        hand[tip] = Point(6, tip)
    return hand


def _ok_hand() -> list[Point]:
    hand = [Point(0, 0) for _ in range(21)]
    hand[3] = Point(20, 0)
    hand[4] = Point(10, 0)
    hand[6] = Point(20, 1)
    hand[8] = Point(10, 1)
    hand[10] = Point(10, 10)
    hand[12] = Point(35, 12)
    hand[14] = Point(10, 14)
    hand[16] = Point(35, 16)
    hand[18] = Point(10, 18)
    hand[20] = Point(35, 20)
    return hand


class OverlayGestureTest(unittest.TestCase):
    def test_overlay_draws_and_encodes_preview(self) -> None:
        frame = np.zeros((120, 160, 3), dtype=np.uint8)
        vision = VisionResult(
            tracking_detection=DetectionResult(BBox(40, 20, 50, 80), 0.9, label="person_pose"),
            person_bbox=BBox(40, 20, 50, 80),
            body_skeleton=[LineSegment(Point(50, 30), Point(80, 70))],
            hand_landmarks=[[Point(float(i * 2), float(i * 3)) for i in range(21)]],
        )

        DeviceOverlayRenderer().draw(
            frame,
            vision=vision,
            selected_template=_template_profile(),
            settings=OverlaySettings(),
            ai_lock_target_box_norm=(0.2, 0.2, 0.2, 0.4),
        )

        ok, encoded = cv2.imencode(".jpg", frame)
        self.assertTrue(ok)
        self.assertGreater(len(encoded.tobytes()), 100)
        self.assertGreater(int(frame.sum()), 0)

    def test_session_preview_overlay_smoke(self) -> None:
        session = object.__new__(DeviceSessionContext)
        session.runtime_state = RuntimeState()
        session.runtime_state.latest_frame = np.zeros((120, 160, 3), dtype=np.uint8)
        session.runtime_state.latest_vision = VisionResult(
            tracking_detection=DetectionResult(BBox(40, 20, 50, 80), 0.9, label="person_pose"),
            person_bbox=BBox(40, 20, 50, 80),
            body_skeleton=[LineSegment(Point(50, 30), Point(80, 70))],
        )
        session.runtime_state.stable_detection = session.runtime_state.latest_vision.tracking_detection
        session.runtime_state.ai_lock_mode_enabled = True
        session.runtime_state.ai_lock_target_box_norm = (0.2, 0.2, 0.2, 0.4)
        session.mirror_view = True
        session._overlay_renderer = DeviceOverlayRenderer()
        session._overlay_settings = OverlaySettings()
        session._selected_template_profile = _template_profile()

        preview = session._build_preview_frame(session.runtime_state.latest_frame)
        ok, encoded = cv2.imencode(".jpg", preview)

        self.assertEqual(preview.shape, (120, 160, 3))
        self.assertTrue(ok)
        self.assertGreater(len(encoded.tobytes()), 100)
        self.assertGreater(int(preview.sum()), 0)

    def test_open_fist_and_ok_gestures(self) -> None:
        state = GestureCaptureState(stable_frames=2, open_hold_min_s=0.05)
        self.assertIsNone(
            state.update([_open_hand()], 1.0, ready_for_pose_capture=True, force_ok_enabled=False)
        )
        self.assertIsNone(
            state.update([_open_hand()], 1.1, ready_for_pose_capture=True, force_ok_enabled=False)
        )
        self.assertIsNone(
            state.update([_fist_hand()], 1.2, ready_for_pose_capture=True, force_ok_enabled=False)
        )
        self.assertEqual(
            state.update([_fist_hand()], 1.3, ready_for_pose_capture=True, force_ok_enabled=False),
            "capture",
        )

        state = GestureCaptureState(stable_frames=2, open_hold_min_s=0.05)
        self.assertIsNone(
            state.update([_ok_hand()], 2.0, ready_for_pose_capture=False, force_ok_enabled=True)
        )
        self.assertEqual(
            state.update([_ok_hand()], 2.1, ready_for_pose_capture=False, force_ok_enabled=True),
            "force_capture",
        )

    def test_config_route_model_exists(self) -> None:
        payload = DeviceRuntimeConfigRequest(
            overlay={
                "enabled": True,
                "show_face_mesh": False,
                "show_hands": False,
                "show_tracking_anchor": True,
            },
            gesture={"capture_enabled": True},
        )
        self.assertTrue(payload.overlay.enabled)
        self.assertFalse(payload.overlay.show_face_mesh)
        self.assertFalse(payload.overlay.show_hands)
        self.assertTrue(payload.overlay.show_tracking_anchor)
        self.assertTrue(payload.gesture.capture_enabled)
        self.assertIn("/api/device/config", {route.path for route in app.routes})

    def test_overlay_settings_accept_compat_aliases(self) -> None:
        settings = OverlaySettings()
        settings.update_from_dict(
            {
                "show_body_skeleton": False,
                "show_face_mesh": False,
                "show_hands": False,
                "show_tracking_anchor": True,
            }
        )

        self.assertFalse(settings.show_live_body_skeleton)
        self.assertFalse(settings.show_live_face_mesh)
        self.assertFalse(settings.show_live_hands)
        self.assertTrue(settings.show_tracking_anchor)

    def test_performance_profile_keeps_tracking_anchor_lightweight(self) -> None:
        cfg = default_config("mobile_push")
        apply_rpi_profile(cfg, RaspberryPiProfile.performance())

        self.assertEqual(cfg.detection.detector_fps, 6.0)
        self.assertEqual(cfg.detection.async_skip_frames, 1)
        self.assertEqual(cfg.detection.max_inference_side, 480)
        self.assertFalse(cfg.detection.enable_pose_landmarks)
        self.assertFalse(cfg.detection.enable_face_landmarks)
        self.assertFalse(cfg.detection.enable_hand_landmarks)
        self.assertEqual(cfg.detection.tracking_anchor_mode, "upper_body")
        self.assertEqual(cfg.app.ui_refresh_fps, 15.0)
        self.assertEqual(cfg.app.preview_scale, 0.5)
        self.assertFalse(cfg.app.show_body_skeleton)
        self.assertFalse(cfg.app.show_face_mesh)
        self.assertFalse(cfg.app.show_hands)
        self.assertTrue(cfg.app.show_tracking_anchor)


if __name__ == "__main__":
    unittest.main()
