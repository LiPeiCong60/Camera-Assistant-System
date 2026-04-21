"""Device repository."""

from __future__ import annotations

from sqlalchemy import select

from backend.app.models.device import Device
from backend.app.repositories.base import Repository


class DeviceRepository(Repository[Device]):
    model = Device

    def get_for_user(self, user_id: int, device_id: int) -> Device | None:
        stmt = select(Device).where(Device.id == device_id).where(Device.user_id == user_id)
        return self.session.scalar(stmt)

    def get_by_device_code(self, device_code: str) -> Device | None:
        stmt = select(Device).where(Device.device_code == device_code)
        return self.session.scalar(stmt)

    def list_all_devices(self) -> list[Device]:
        stmt = select(Device).order_by(Device.id.asc())
        return list(self.session.scalars(stmt))
