"""Device schemas."""

from __future__ import annotations

from datetime import datetime

from backend.app.schemas.base import SchemaModel


class DeviceRead(SchemaModel):
    id: int
    user_id: int
    device_code: str
    device_name: str
    device_type: str
    serial_number: str | None = None
    local_ip: str | None = None
    control_base_url: str | None = None
    firmware_version: str | None = None
    status: str
    is_online: bool
    last_seen_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class DeviceWriteRequest(SchemaModel):
    user_id: int
    device_code: str
    device_name: str
    device_type: str = "raspberry_pi"
    serial_number: str | None = None
    local_ip: str | None = None
    control_base_url: str | None = None
    firmware_version: str | None = None
    status: str = "offline"
    is_online: bool = False
