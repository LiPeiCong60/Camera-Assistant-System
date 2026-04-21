"""Repository for AI provider configuration."""

from __future__ import annotations

from sqlalchemy import select

from backend.app.models.ai_provider_config import AiProviderConfig
from backend.app.repositories.base import Repository


class AiProviderConfigRepository(Repository[AiProviderConfig]):
    model = AiProviderConfig

    def list_all(self) -> list[AiProviderConfig]:
        stmt = select(AiProviderConfig).order_by(
            AiProviderConfig.is_default.desc(),
            AiProviderConfig.enabled.desc(),
            AiProviderConfig.id.asc(),
        )
        return list(self.session.scalars(stmt))

    def get_by_provider_code(self, provider_code: str) -> AiProviderConfig | None:
        stmt = select(AiProviderConfig).where(AiProviderConfig.provider_code == provider_code)
        return self.session.scalar(stmt)

    def get_default(self) -> AiProviderConfig | None:
        default_stmt = (
            select(AiProviderConfig)
            .where(AiProviderConfig.is_default.is_(True))
            .order_by(AiProviderConfig.id.asc())
            .limit(1)
        )
        config = self.session.scalar(default_stmt)
        if config is not None:
            return config

        enabled_stmt = (
            select(AiProviderConfig)
            .where(AiProviderConfig.enabled.is_(True))
            .order_by(AiProviderConfig.id.asc())
            .limit(1)
        )
        config = self.session.scalar(enabled_stmt)
        if config is not None:
            return config

        stmt = select(AiProviderConfig).order_by(AiProviderConfig.id.asc()).limit(1)
        return self.session.scalar(stmt)
