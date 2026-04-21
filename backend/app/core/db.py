"""Database helpers for backend service."""

from __future__ import annotations

from functools import lru_cache

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker


def get_database_status(database_url: str) -> dict:
    if not database_url:
        return {
            "configured": False,
            "driver": None,
            "connected": False,
            "message": "DATABASE_URL is not configured",
        }

    driver = database_url.split("://", 1)[0] if "://" in database_url else "unknown"
    status = {
        "configured": True,
        "driver": driver,
        "connected": False,
        "message": "database url configured",
    }

    engine = get_engine(database_url)
    if engine is None:
        return status

    try:
        with engine.connect() as connection:
            current_database = connection.execute(text("SELECT current_database()")).scalar_one()
        status["connected"] = True
        status["database"] = current_database
        status["message"] = "database connected"
    except Exception as exc:
        status["message"] = f"database connection failed: {exc}"

    return status


@lru_cache(maxsize=1)
def get_engine(database_url: str) -> Engine | None:
    if not database_url:
        return None
    return create_engine(database_url, future=True, pool_pre_ping=True)


@lru_cache(maxsize=1)
def get_session_factory(database_url: str):
    engine = get_engine(database_url)
    if engine is None:
        return None
    return sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False, class_=Session)


def init_database(database_url: str) -> dict:
    engine = get_engine(database_url)
    if engine is None:
        raise RuntimeError("DATABASE_URL is not configured")

    from backend.app.models import Base

    Base.metadata.create_all(engine)
    _apply_schema_compatibility_patches(engine)
    return {
        "created_tables": sorted(Base.metadata.tables.keys()),
    }


def _apply_schema_compatibility_patches(engine: Engine) -> None:
    statements = [
        """
        ALTER TABLE IF EXISTS capture_sessions
        DROP CONSTRAINT IF EXISTS chk_capture_sessions_mode
        """,
        """
        ALTER TABLE IF EXISTS capture_sessions
        ADD CONSTRAINT chk_capture_sessions_mode CHECK (
            mode IN ('mobile_only', 'device_link', 'MANUAL', 'AUTO_TRACK', 'SMART_COMPOSE')
        )
        """,
        """
        ALTER TABLE IF EXISTS captures
        DROP CONSTRAINT IF EXISTS chk_captures_type
        """,
        """
        ALTER TABLE IF EXISTS captures
        ADD CONSTRAINT chk_captures_type CHECK (
            capture_type IN ('single', 'photo', 'burst', 'best', 'background')
        )
        """,
        """
        ALTER TABLE IF EXISTS ai_provider_configs
        ADD COLUMN IF NOT EXISTS vendor_name VARCHAR(64) NOT NULL DEFAULT 'custom'
        """,
        """
        ALTER TABLE IF EXISTS ai_provider_configs
        ADD COLUMN IF NOT EXISTS provider_format VARCHAR(32) NOT NULL DEFAULT 'openai_compatible'
        """,
        """
        ALTER TABLE IF EXISTS ai_provider_configs
        ADD COLUMN IF NOT EXISTS is_default BOOLEAN NOT NULL DEFAULT FALSE
        """,
        """
        ALTER TABLE IF EXISTS ai_provider_configs
        ADD COLUMN IF NOT EXISTS notes TEXT
        """,
        """
        UPDATE ai_provider_configs
        SET is_default = TRUE
        WHERE id = (
            SELECT id
            FROM ai_provider_configs
            ORDER BY enabled DESC, id ASC
            LIMIT 1
        )
        AND NOT EXISTS (
            SELECT 1 FROM ai_provider_configs WHERE is_default = TRUE
        )
        """,
        """
        ALTER TABLE IF EXISTS templates
        ADD COLUMN IF NOT EXISTS is_recommended_default BOOLEAN NOT NULL DEFAULT FALSE
        """,
        """
        ALTER TABLE IF EXISTS templates
        ADD COLUMN IF NOT EXISTS recommended_sort_order INTEGER NOT NULL DEFAULT 0
        """,
    ]
    with engine.begin() as connection:
        for statement in statements:
            connection.execute(text(statement))
