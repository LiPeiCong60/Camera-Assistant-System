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
        UPDATE capture_sessions
        SET mode = CASE mode
            WHEN 'device_link' THEN 'gimbal_manual'
            WHEN 'MANUAL' THEN 'gimbal_manual'
            WHEN 'AUTO_TRACK' THEN 'gimbal_follow'
            WHEN 'SMART_COMPOSE' THEN 'gimbal_template'
            ELSE mode
        END
        WHERE mode IN ('device_link', 'MANUAL', 'AUTO_TRACK', 'SMART_COMPOSE')
        """,
        """
        ALTER TABLE IF EXISTS capture_sessions
        ADD CONSTRAINT chk_capture_sessions_mode CHECK (
            mode IN ('mobile_only', 'gimbal_manual', 'gimbal_follow', 'gimbal_template', 'ai_auto_angle', 'ai_background')
        )
        """,
        """
        ALTER TABLE IF EXISTS captures
        DROP CONSTRAINT IF EXISTS chk_captures_type
        """,
        """
        UPDATE captures
        SET metadata = (
            COALESCE(metadata::jsonb, '{}'::jsonb) || jsonb_build_object('media_type', 'photo')
        )::json
        WHERE capture_type = 'photo'
        """,
        """
        UPDATE captures
        SET metadata = (
            COALESCE(metadata::jsonb, '{}'::jsonb) || jsonb_build_object(
            'media_type',
            COALESCE(metadata->>'media_type', 'photo'),
            'source',
            'device_link'
            )
        )::json
        WHERE capture_type = 'device_link'
        """,
        """
        UPDATE captures
        SET capture_type = 'single'
        WHERE capture_type IN ('photo', 'device_link')
        """,
        """
        ALTER TABLE IF EXISTS captures
        ADD CONSTRAINT chk_captures_type CHECK (
            capture_type IN ('single', 'burst', 'best', 'background', 'template', 'recording')
        )
        """,
        """
        ALTER TABLE IF EXISTS ai_tasks
        DROP CONSTRAINT IF EXISTS chk_ai_tasks_type
        """,
        """
        UPDATE ai_tasks
        SET task_type = CASE task_type
            WHEN 'background_lock' THEN 'analyze_background'
            WHEN 'analyze_template' THEN 'template_match'
            ELSE task_type
        END
        WHERE task_type IN ('background_lock', 'analyze_template')
        """,
        """
        UPDATE ai_tasks
        SET response_payload = (
            jsonb_set(
            response_payload::jsonb,
            '{task_type}',
            to_jsonb((CASE response_payload->>'task_type'
                WHEN 'background_lock' THEN 'analyze_background'
                WHEN 'analyze_template' THEN 'template_match'
                ELSE response_payload->>'task_type'
            END)::text)
            )
        )::json
        WHERE response_payload IS NOT NULL
          AND response_payload::jsonb ? 'task_type'
          AND response_payload->>'task_type' IN ('background_lock', 'analyze_template')
        """,
        """
        ALTER TABLE IF EXISTS ai_tasks
        ADD CONSTRAINT chk_ai_tasks_type CHECK (
            task_type IN ('analyze_photo', 'analyze_background', 'batch_pick', 'auto_angle', 'template_match', 'video_analysis')
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
