from __future__ import annotations

import unittest
from datetime import datetime, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from backend.app.models import Base, Capture, CaptureSession, User


class CaptureTypeTest(unittest.TestCase):
    def test_device_link_capture_type_can_be_persisted(self) -> None:
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
            capture_session = CaptureSession(
                id=1,
                session_code="device-link-session",
                user_id=1,
                mode="device_link",
                status="opened",
                started_at=datetime.now(timezone.utc),
            )
            capture = Capture(
                id=1,
                session_id=1,
                user_id=1,
                capture_type="device_link",
                file_url="http://example.test/uploads/capture.jpg",
                storage_provider="local_static",
            )

            session.add_all([user, capture_session, capture])
            session.commit()

            persisted = session.get(Capture, 1)
            self.assertIsNotNone(persisted)
            self.assertEqual(persisted.capture_type, "device_link")


if __name__ == "__main__":
    unittest.main()
