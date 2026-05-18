from __future__ import annotations

from types import SimpleNamespace
import unittest

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from backend.app.api.routes.mobile import _build_upload_file_parts, _is_supported_capture_upload
from backend.app.models import Base, User
from backend.app.schemas.capture import CaptureCreateRequest
from backend.app.schemas.capture_session import CaptureSessionCreateRequest
from backend.app.services.mobile_service import MobileService


class CaptureTypeTest(unittest.TestCase):
    def test_legacy_device_link_values_are_mapped_before_persisting(self) -> None:
        engine = create_engine("sqlite:///:memory:")
        Base.metadata.create_all(engine)

        with Session(engine) as session:
            user = User(
                id=1,
                user_code="U001",
                display_name="User",
                role="user",
                status="active",
            )
            session.add(user)
            session.commit()

            service = MobileService(session)
            capture_session = service.create_capture_session(
                user,
                CaptureSessionCreateRequest(mode="device_link"),
            )
            capture = service.create_capture(
                user,
                CaptureCreateRequest(
                    session_id=capture_session.id,
                    capture_type="device_link",
                    file_url="http://example.test/uploads/capture.jpg",
                    storage_provider="local_static",
                    local_album_saved=True,
                ),
            )

            self.assertEqual(capture_session.mode, "gimbal_manual")
            self.assertEqual(capture.capture_type, "single")
            self.assertEqual(capture.capture_metadata["source"], "device_link")
            self.assertEqual(capture.capture_metadata["media_type"], "photo")
            self.assertTrue(capture.capture_metadata["local_album_saved"])

    def test_mobile_capture_file_upload_accepts_video_files(self) -> None:
        upload = SimpleNamespace(filename="recording.mp4", content_type="video/mp4")

        self.assertTrue(_is_supported_capture_upload(upload))
        self.assertEqual(_build_upload_file_parts(upload), ("recording.mp4", ".mp4"))

    def test_mobile_capture_file_upload_infers_video_suffix(self) -> None:
        upload = SimpleNamespace(filename="recording.tmp", content_type="video/webm")

        self.assertTrue(_is_supported_capture_upload(upload))
        self.assertEqual(_build_upload_file_parts(upload), ("recording.tmp", ".webm"))


if __name__ == "__main__":
    unittest.main()
