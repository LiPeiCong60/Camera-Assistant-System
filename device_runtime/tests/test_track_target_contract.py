from __future__ import annotations

import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from device_runtime.api import session_manager as session_config
from device_runtime.api.routes import control as control_routes
from device_runtime.config import TrackingConfig, default_config
from device_runtime.control.tracking_controller import TrackingController
from device_runtime.interfaces.target_strategy import TargetPreset, build_target_strategy
from device_runtime.mode_manager import ModeManager
from device_runtime.services.control_service import ControlService
from device_runtime.services.runtime_state import RuntimeState


class FakeGimbal:
    def __init__(self) -> None:
        self.pan = 0.0
        self.tilt = 0.0
        self.moves: list[tuple[float, float, bool]] = []

    def move_relative(self, pan_delta: float, tilt_delta: float, smooth: bool = True) -> None:
        self.moves.append((pan_delta, tilt_delta, smooth))
        self.pan += pan_delta
        self.tilt += tilt_delta

    def get_current_angles(self, prefer_feedback: bool = True) -> tuple[float, float]:
        return self.pan, self.tilt


def _tracking_config(**overrides: object) -> TrackingConfig:
    values = {
        "deadzone_px": 30,
        "debounce_frames": 1,
        "gain_x": 0.01,
        "gain_y": 0.01,
        "max_delta_deg": 3.0,
        "min_command_interval_s": 0.0,
        "command_smooth_alpha": 1.0,
        "min_output_deg": 0.0,
        "max_anchor_jump_px": 10_000.0,
        "settle_after_move_s": 0.0,
    }
    values.update(overrides)
    return TrackingConfig(**values)


def _build_session(**tracking_overrides: object) -> tuple[SimpleNamespace, FakeGimbal]:
    gimbal = FakeGimbal()
    service = ControlService(
        mode_manager=ModeManager(),
        tracking=TrackingController(
            _tracking_config(**tracking_overrides),
            build_target_strategy(TargetPreset.CENTER),
        ),
        gimbal=gimbal,
        runtime_state=RuntimeState(),
        manual_step_deg=3.0,
    )
    return SimpleNamespace(control_service=service), gimbal


def _call_track_target(session: SimpleNamespace, **payload: object) -> dict:
    with patch.object(control_routes, "require_session", return_value=session):
        return control_routes.track_target(control_routes.TrackTargetRequest(**payload))


class TrackTargetContractTest(unittest.TestCase):
    def test_center_deadzone_does_not_move_gimbal(self) -> None:
        session, gimbal = _build_session()

        response = _call_track_target(
            session,
            target_x=0.5,
            target_y=0.5,
            confidence=1.0,
            frame={"width": 1000, "height": 1000},
        )

        self.assertTrue(response["success"])
        self.assertFalse(response["data"]["applied"])
        self.assertEqual(response["data"]["pan_delta"], 0.0)
        self.assertEqual(response["data"]["tilt_delta"], 0.0)
        self.assertEqual(gimbal.moves, [])

    def test_right_and_down_target_produces_default_pan_left_tilt_down_command(self) -> None:
        session, gimbal = _build_session()

        response = _call_track_target(
            session,
            target={"type": "shoulder_center", "x": 0.75, "y": 0.75},
            confidence=1.0,
            frame={"width": 1000, "height": 1000},
        )

        self.assertTrue(response["data"]["applied"])
        self.assertLess(response["data"]["pan_delta"], 0.0)
        self.assertGreater(response["data"]["tilt_delta"], 0.0)
        self.assertEqual(response["data"]["target_type"], "shoulder_center")
        self.assertEqual(len(gimbal.moves), 1)
        pan_delta, tilt_delta, smooth = gimbal.moves[0]
        self.assertLess(pan_delta, 0.0)
        self.assertGreater(tilt_delta, 0.0)
        self.assertFalse(smooth)

    def test_out_of_range_normalized_target_is_clamped_before_tracking(self) -> None:
        session, gimbal = _build_session()

        response = _call_track_target(
            session,
            target_type="face_center",
            target_x=1.4,
            target_y=-0.5,
            confidence=1.5,
            frame={"width": 1000, "height": 1000},
        )

        self.assertTrue(response["data"]["applied"])
        self.assertEqual(response["data"]["target_x"], 1.0)
        self.assertEqual(response["data"]["target_y"], 0.0)
        self.assertEqual(response["data"]["desired_x"], 0.5)
        self.assertEqual(response["data"]["desired_y"], 0.5)
        self.assertEqual(response["data"]["confidence"], 1.0)
        self.assertEqual(response["data"]["target_type"], "face_center")
        self.assertEqual(response["data"]["pan_delta"], -0.99)
        self.assertEqual(response["data"]["tilt_delta"], -0.99)
        self.assertAlmostEqual(gimbal.moves[0][0], -0.99)
        self.assertAlmostEqual(gimbal.moves[0][1], -0.99)
        self.assertFalse(gimbal.moves[0][2])

    def test_desired_anchor_allows_template_alignment_without_centering(self) -> None:
        session, gimbal = _build_session()

        response = _call_track_target(
            session,
            target_type="shoulder_center",
            target_x=0.72,
            target_y=0.32,
            desired_x=0.62,
            desired_y=0.32,
            confidence=1.0,
            frame={"width": 1000, "height": 1000},
        )

        self.assertTrue(response["data"]["applied"])
        self.assertEqual(response["data"]["desired_x"], 0.62)
        self.assertEqual(response["data"]["desired_y"], 0.32)
        self.assertLess(response["data"]["pan_delta"], 0.0)
        self.assertAlmostEqual(response["data"]["tilt_delta"], 0.0)
        self.assertEqual(len(gimbal.moves), 1)

    def test_matching_desired_anchor_does_not_move_gimbal(self) -> None:
        session, gimbal = _build_session()

        response = _call_track_target(
            session,
            target={"type": "face_center", "x": 0.64, "y": 0.22},
            desired_x=0.64,
            desired_y=0.22,
            confidence=1.0,
            frame={"width": 1000, "height": 1000},
        )

        self.assertTrue(response["success"])
        self.assertFalse(response["data"]["applied"])
        self.assertEqual(gimbal.moves, [])

    def test_low_confidence_below_tracking_threshold_is_ignored(self) -> None:
        session, gimbal = _build_session(min_confidence=0.6)

        response = _call_track_target(
            session,
            target_x=0.9,
            target_y=0.9,
            confidence=0.2,
            frame={"width": 1000, "height": 1000},
        )

        self.assertTrue(response["success"])
        self.assertFalse(response["data"]["applied"])
        self.assertEqual(response["data"]["confidence"], 0.2)
        self.assertEqual(gimbal.moves, [])

    def test_tracking_env_overrides_runtime_config_fields(self) -> None:
        overrides = {
            "DEVICE_TRACKING_MIN_CONFIDENCE": "0.65",
            "DEVICE_TRACKING_DEADZONE_PX": "12",
            "DEVICE_TRACKING_DEBOUNCE_FRAMES": "3",
            "DEVICE_TRACKING_GAIN_X": "0.11",
            "DEVICE_TRACKING_GAIN_Y": "0.12",
            "DEVICE_TRACKING_MAX_DELTA_DEG": "1.7",
            "DEVICE_TRACKING_MIN_COMMAND_INTERVAL_S": "0.04",
            "DEVICE_TRACKING_COMMAND_SMOOTH_ALPHA": "0.5",
            "DEVICE_TRACKING_MIN_OUTPUT_DEG": "0.09",
            "DEVICE_TRACKING_MAX_ANCHOR_JUMP_PX": "90",
            "DEVICE_TRACKING_SETTLE_AFTER_MOVE_S": "0.11",
            "DEVICE_TRACKING_INVERT_PAN": "true",
            "DEVICE_TRACKING_INVERT_TILT": "on",
        }
        with patch.dict(os.environ, overrides, clear=True):
            cfg = default_config("mobile_push")
            session_config._apply_runtime_env_overrides(cfg)

        self.assertAlmostEqual(cfg.tracking.min_confidence, 0.65)
        self.assertEqual(cfg.tracking.deadzone_px, 12)
        self.assertEqual(cfg.tracking.debounce_frames, 3)
        self.assertAlmostEqual(cfg.tracking.gain_x, 0.11)
        self.assertAlmostEqual(cfg.tracking.gain_y, 0.12)
        self.assertAlmostEqual(cfg.tracking.max_delta_deg, 1.7)
        self.assertAlmostEqual(cfg.tracking.min_command_interval_s, 0.04)
        self.assertAlmostEqual(cfg.tracking.command_smooth_alpha, 0.5)
        self.assertAlmostEqual(cfg.tracking.min_output_deg, 0.09)
        self.assertAlmostEqual(cfg.tracking.max_anchor_jump_px, 90.0)
        self.assertAlmostEqual(cfg.tracking.settle_after_move_s, 0.11)
        self.assertTrue(cfg.tracking.invert_pan)
        self.assertTrue(cfg.tracking.invert_tilt)


if __name__ == "__main__":
    unittest.main()
