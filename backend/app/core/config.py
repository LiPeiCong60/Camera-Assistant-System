"""Application settings for backend service."""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]


@dataclass(frozen=True)
class Settings:
    app_name: str = "Camera Assistant Backend"
    environment: str = "development"
    version: str = "0.1.0"
    host: str = "0.0.0.0"
    port: int = 8000
    database_url: str = ""
    auth_secret: str = "camera-assistant-dev-secret"
    access_token_ttl_seconds: int = 86400
    uploads_dir: str = str(REPO_ROOT / "uploads")
    uploads_url_path: str = "/uploads"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings(
        app_name=os.getenv("BACKEND_APP_NAME", "Camera Assistant Backend"),
        environment=os.getenv("BACKEND_ENV", "development"),
        version=os.getenv("BACKEND_VERSION", "0.1.0"),
        host=os.getenv("BACKEND_HOST", "0.0.0.0"),
        port=int(os.getenv("BACKEND_PORT", "8000")),
        database_url=os.getenv("DATABASE_URL", ""),
        auth_secret=os.getenv("BACKEND_AUTH_SECRET", "camera-assistant-dev-secret"),
        access_token_ttl_seconds=int(os.getenv("BACKEND_ACCESS_TOKEN_TTL_SECONDS", "86400")),
        uploads_dir=os.getenv("BACKEND_UPLOADS_DIR", str(REPO_ROOT / "uploads")),
        uploads_url_path=os.getenv("BACKEND_UPLOADS_URL_PATH", "/uploads"),
    )
