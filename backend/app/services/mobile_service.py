"""Mobile-facing backend service helpers."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from backend.app.models.ai_provider_config import AiProviderConfig
from backend.app.models.ai_task import AiTask
from backend.app.models.base import Base
from backend.app.models.capture import Capture
from backend.app.models.capture_session import CaptureSession
from backend.app.models.template import Template
from backend.app.models.user import User
from backend.app.repositories.ai_provider_config_repository import AiProviderConfigRepository
from backend.app.repositories.ai_task_repository import AiTaskRepository
from backend.app.repositories.capture_repository import CaptureRepository
from backend.app.repositories.capture_session_repository import CaptureSessionRepository
from backend.app.repositories.device_repository import DeviceRepository
from backend.app.repositories.plan_repository import PlanRepository
from backend.app.repositories.template_repository import TemplateRepository
from backend.app.repositories.user_subscription_repository import UserSubscriptionRepository
from backend.app.schemas.ai_task import AnalyzeBackgroundRequest, AnalyzePhotoRequest, BatchPickRequest
from backend.app.schemas.capture import CaptureCreateRequest
from backend.app.schemas.capture_session import CaptureSessionCreateRequest
from backend.app.schemas.template import TemplateCreateRequest
from backend.app.services.ai_provider_service import AiProviderInvocationError, AiProviderService
from backend.app.services.template_pose_service import TemplatePoseService


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _next_id(session: Session, model: type[Base]) -> int:
    max_id = session.scalar(select(func.max(model.id)))
    return int(max_id or 0) + 1


def _build_code(prefix: str) -> str:
    return f"{prefix}_{_utcnow().strftime('%Y%m%d_%H%M%S_%f')}"


def _mock_background_lock_result() -> dict[str, object]:
    return {
        "task_type": "background_lock",
        "recommended_pan_delta": 2.0,
        "recommended_tilt_delta": -1.0,
        "target_box_norm": [0.31, 0.14, 0.36, 0.70],
        "summary": "背景更干净的机位已经计算完成，可以切到建议位置。",
        "score": 91,
    }


class MobileService:
    def __init__(self, session: Session) -> None:
        self.session = session
        self.ai_provider_config_repo = AiProviderConfigRepository(session)
        self.plan_repo = PlanRepository(session)
        self.subscription_repo = UserSubscriptionRepository(session)
        self.template_repo = TemplateRepository(session)
        self.device_repo = DeviceRepository(session)
        self.capture_session_repo = CaptureSessionRepository(session)
        self.capture_repo = CaptureRepository(session)
        self.ai_task_repo = AiTaskRepository(session)

    def list_plans(self):
        return self.plan_repo.list_active()

    def get_subscription(self, user: User):
        return self.subscription_repo.get_current_for_user(user.id)

    def list_templates(self, user: User):
        return self.template_repo.list_available_for_user(user.id)

    def create_template(self, user: User, payload: TemplateCreateRequest) -> Template:
        template_data = payload.template_data
        if not template_data:
            if not payload.source_image_url:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="template_data or source_image_url is required",
                )
            template_data = TemplatePoseService().create_template_data(
                name=payload.name,
                source_image_url=payload.source_image_url,
            )

        template = Template(
            id=_next_id(self.session, Template),
            user_id=user.id,
            name=payload.name,
            template_type=payload.template_type,
            source_image_url=payload.source_image_url,
            preview_image_url=payload.preview_image_url,
            template_data=template_data,
            status="active",
        )
        self.template_repo.add(template)
        self.session.commit()
        self.session.refresh(template)
        return template

    def delete_template(self, user: User, template_id: int) -> Template:
        template = self.template_repo.get_for_user(user.id, template_id)
        if template is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="template not found")

        template.status = "deleted"
        self.session.commit()
        self.session.refresh(template)
        return template

    def create_capture_session(self, user: User, payload: CaptureSessionCreateRequest) -> CaptureSession:
        if payload.device_id is not None and self.device_repo.get_for_user(user.id, payload.device_id) is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="device not found")

        if (
            payload.template_id is not None
            and self.template_repo.get_accessible_for_user(user.id, payload.template_id) is None
        ):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="template not found")

        capture_session = CaptureSession(
            id=_next_id(self.session, CaptureSession),
            session_code=_build_code("SES"),
            user_id=user.id,
            device_id=payload.device_id,
            template_id=payload.template_id,
            mode=payload.mode,
            status="opened",
            started_at=_utcnow(),
            session_metadata=payload.metadata,
        )
        self.capture_session_repo.add(capture_session)
        self.session.commit()
        self.session.refresh(capture_session)
        return capture_session

    def list_history_sessions(self, user: User):
        return self.capture_session_repo.list_by_user(user.id)

    def create_capture(self, user: User, payload: CaptureCreateRequest) -> Capture:
        session_entity = self.capture_session_repo.get_for_user(user.id, payload.session_id)
        if session_entity is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="capture session not found")

        capture = Capture(
            id=_next_id(self.session, Capture),
            session_id=payload.session_id,
            user_id=user.id,
            capture_type=payload.capture_type,
            file_url=payload.file_url,
            thumbnail_url=payload.thumbnail_url,
            width=payload.width,
            height=payload.height,
            storage_provider=payload.storage_provider,
            is_ai_selected=payload.is_ai_selected,
            score=payload.score,
            capture_metadata=payload.metadata,
        )
        self.capture_repo.add(capture)
        self.session.commit()
        self.session.refresh(capture)
        return capture

    def list_history_captures(self, user: User):
        return self.capture_repo.list_by_user(user.id)

    def create_analyze_photo_task(self, user: User, payload: AnalyzePhotoRequest) -> AiTask:
        capture = self._validate_session_capture(user, payload.session_id, payload.capture_id)
        config, provider_name, provider_metadata = self._resolve_ai_provider(user)

        if config is None:
            return self._create_failed_ai_task(
                user=user,
                session_id=payload.session_id,
                capture_id=payload.capture_id,
                task_type="analyze_photo",
                provider_name="unconfigured_ai",
                request_payload=payload.model_dump(),
                provider_metadata={**provider_metadata, "mode": "provider_not_configured"},
                error_message="AI provider is not configured. Please configure an enabled provider in admin settings.",
            )

        if provider_metadata["mode"] != "real_provider_ready":
            return self._create_failed_ai_task(
                user=user,
                session_id=payload.session_id,
                capture_id=payload.capture_id,
                task_type="analyze_photo",
                provider_name=config.provider_code,
                request_payload=payload.model_dump(),
                provider_metadata=provider_metadata,
                error_message=self._build_provider_not_ready_message(config, provider_metadata),
            )

        try:
            response_payload = AiProviderService(config).analyze_photo(capture, provider_metadata)
        except AiProviderInvocationError as exc:
            return self._create_failed_ai_task(
                user=user,
                session_id=payload.session_id,
                capture_id=payload.capture_id,
                task_type="analyze_photo",
                provider_name=provider_name,
                request_payload=payload.model_dump(),
                provider_metadata={**provider_metadata, "mode": "real_provider_failed"},
                error_message=str(exc),
            )

        return self._create_success_ai_task(
            user=user,
            session_id=payload.session_id,
            capture_id=payload.capture_id,
            device_id=None,
            task_type="analyze_photo",
            provider_name=provider_name,
            request_payload=payload.model_dump(),
            response_payload=response_payload,
        )

    def create_analyze_background_task(self, user: User, payload: AnalyzeBackgroundRequest) -> AiTask:
        capture = self._validate_session_capture(user, payload.session_id, payload.capture_id)
        if payload.device_id is not None and self.device_repo.get_for_user(user.id, payload.device_id) is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="device not found")

        config, provider_name, provider_metadata = self._resolve_ai_provider(user)

        if config is None:
            return self._create_failed_ai_task(
                user=user,
                session_id=payload.session_id,
                capture_id=payload.capture_id,
                task_type="analyze_background",
                provider_name="unconfigured_ai",
                request_payload=payload.model_dump(),
                provider_metadata={**provider_metadata, "mode": "provider_not_configured"},
                error_message="AI provider is not configured. Please configure an enabled provider in admin settings.",
                device_id=payload.device_id,
            )

        if provider_metadata["mode"] != "real_provider_ready":
            return self._create_failed_ai_task(
                user=user,
                session_id=payload.session_id,
                capture_id=payload.capture_id,
                task_type="analyze_background",
                provider_name=config.provider_code,
                request_payload=payload.model_dump(),
                provider_metadata=provider_metadata,
                error_message=self._build_provider_not_ready_message(config, provider_metadata),
                device_id=payload.device_id,
            )

        try:
            response_payload = AiProviderService(config).analyze_background(capture, provider_metadata)
        except AiProviderInvocationError as exc:
            return self._create_failed_ai_task(
                user=user,
                session_id=payload.session_id,
                capture_id=payload.capture_id,
                task_type="analyze_background",
                provider_name=provider_name,
                request_payload=payload.model_dump(),
                provider_metadata={**provider_metadata, "mode": "real_provider_failed"},
                error_message=str(exc),
                device_id=payload.device_id,
            )

        return self._create_success_ai_task(
            user=user,
            session_id=payload.session_id,
            capture_id=payload.capture_id,
            device_id=payload.device_id,
            task_type="analyze_background",
            provider_name=provider_name,
            request_payload=payload.model_dump(),
            response_payload=response_payload,
        )

    def create_batch_pick_task(self, user: User, payload: BatchPickRequest) -> tuple[AiTask, int | None]:
        session_entity = self.capture_session_repo.get_for_user(user.id, payload.session_id)
        if session_entity is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="capture session not found")

        config, provider_name, provider_metadata = self._resolve_ai_provider(user)
        captures = self.capture_repo.list_by_user_and_ids(user.id, payload.capture_ids)
        if len(captures) != len(payload.capture_ids):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="one or more captures not found")
        if any(capture.session_id != payload.session_id for capture in captures):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="all captures must belong to the same session")
        if len(captures) < 2:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="batch-pick requires at least two captures")

        if config is None:
            task = self._create_failed_ai_task(
                user=user,
                session_id=payload.session_id,
                capture_id=None,
                task_type="batch_pick",
                provider_name="unconfigured_ai",
                request_payload=payload.model_dump(),
                provider_metadata={**provider_metadata, "mode": "provider_not_configured"},
                error_message="AI provider is not configured. Please configure an enabled provider in admin settings.",
            )
            return task, None

        if provider_metadata["mode"] != "real_provider_ready":
            task = self._create_failed_ai_task(
                user=user,
                session_id=payload.session_id,
                capture_id=None,
                task_type="batch_pick",
                provider_name=config.provider_code,
                request_payload=payload.model_dump(),
                provider_metadata=provider_metadata,
                error_message=self._build_provider_not_ready_message(config, provider_metadata),
            )
            return task, None

        try:
            response_payload = AiProviderService(config).batch_pick(captures, provider_metadata)
        except AiProviderInvocationError as exc:
            task = self._create_failed_ai_task(
                user=user,
                session_id=payload.session_id,
                capture_id=None,
                task_type="batch_pick",
                provider_name=provider_name,
                request_payload=payload.model_dump(),
                provider_metadata={**provider_metadata, "mode": "real_provider_failed"},
                error_message=str(exc),
            )
            return task, None

        best_capture_id = int(response_payload["best_capture_id"])
        for capture in captures:
            capture.is_ai_selected = capture.id == best_capture_id
        best_capture = next(capture for capture in captures if capture.id == best_capture_id)

        task = self._create_success_ai_task(
            user=user,
            session_id=payload.session_id,
            capture_id=best_capture_id,
            device_id=None,
            task_type="batch_pick",
            provider_name=provider_name,
            request_payload=payload.model_dump(),
            response_payload=response_payload,
        )
        self.session.commit()
        self.session.refresh(task)
        self.session.refresh(best_capture)
        return task, best_capture_id

    def get_ai_task(self, user: User, task_id: int) -> AiTask:
        task = self.ai_task_repo.get_for_user(user.id, task_id)
        if task is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ai task not found")
        return task

    def _validate_session_capture(self, user: User, session_id: int, capture_id: int) -> Capture:
        session_entity = self.capture_session_repo.get_for_user(user.id, session_id)
        if session_entity is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="capture session not found")

        capture = self.capture_repo.get_for_user(user.id, capture_id)
        if capture is None or capture.session_id != session_id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="capture not found")
        return capture

    def _resolve_ai_provider(
        self, user: User
    ) -> tuple[AiProviderConfig | None, str, dict[str, Any]]:
        subscription = self.subscription_repo.get_current_for_user(user.id)
        selected_plan = subscription.plan if subscription is not None else None
        selected_feature_flags = selected_plan.feature_flags if selected_plan is not None else {}

        config = None
        selection_mode = "system_default"
        requested_provider_code = None

        if isinstance(selected_feature_flags, dict):
            requested_provider_code = selected_feature_flags.get("default_ai_provider_code")
            available_provider_codes = selected_feature_flags.get("available_ai_provider_codes") or []

            if isinstance(requested_provider_code, str) and requested_provider_code.strip():
                config = self.ai_provider_config_repo.get_by_provider_code(requested_provider_code.strip())
                selection_mode = "plan_default"

            if config is None and isinstance(available_provider_codes, list):
                for provider_code in available_provider_codes:
                    if not isinstance(provider_code, str) or not provider_code.strip():
                        continue
                    config = self.ai_provider_config_repo.get_by_provider_code(provider_code.strip())
                    if config is not None:
                        requested_provider_code = provider_code.strip()
                        selection_mode = "plan_available_first"
                        break

        if config is None:
            config = self.ai_provider_config_repo.get_default()

        if config is None:
            provider_metadata = {
                "mode": "provider_not_configured",
                "configured": False,
                "selection_mode": selection_mode,
                "requested_provider_code": requested_provider_code,
                "plan_id": selected_plan.id if selected_plan is not None else None,
                "plan_code": selected_plan.plan_code if selected_plan is not None else None,
                "subscription_id": subscription.id if subscription is not None else None,
            }
            return None, "unconfigured_ai", provider_metadata

        is_ready = bool(config.enabled and config.api_key and config.api_base_url and config.model_name)
        provider_name = config.provider_code
        provider_metadata = {
            "mode": "real_provider_ready" if is_ready else "provider_not_ready",
            "configured": True,
            "provider_code": config.provider_code,
            "vendor_name": config.vendor_name,
            "provider_format": config.provider_format,
            "display_name": config.display_name,
            "api_base_url": config.api_base_url,
            "model_name": config.model_name,
            "enabled": config.enabled,
            "is_default": config.is_default,
            "has_api_key": bool(config.api_key),
            "selection_mode": selection_mode,
            "requested_provider_code": requested_provider_code,
            "plan_id": selected_plan.id if selected_plan is not None else None,
            "plan_code": selected_plan.plan_code if selected_plan is not None else None,
            "subscription_id": subscription.id if subscription is not None else None,
        }
        return config, provider_name, provider_metadata

    def _build_provider_not_ready_message(
        self,
        config: AiProviderConfig,
        provider_metadata: dict[str, Any],
    ) -> str:
        issues: list[str] = []
        if not config.enabled:
            issues.append("provider disabled")
        if not config.api_key:
            issues.append("missing api_key")
        if not config.api_base_url:
            issues.append("missing api_base_url")
        if not config.model_name:
            issues.append("missing model_name")
        if not issues:
            issues.append(str(provider_metadata.get("mode") or "provider not ready"))
        return (
            f"AI provider `{config.provider_code}` is not ready: "
            + ", ".join(issues)
            + ". Please update the provider config in admin settings."
        )

    def _create_success_ai_task(
        self,
        *,
        user: User,
        session_id: int,
        capture_id: int | None,
        device_id: int | None,
        task_type: str,
        provider_name: str,
        request_payload: dict[str, Any],
        response_payload: dict[str, Any],
    ) -> AiTask:
        task = AiTask(
            id=_next_id(self.session, AiTask),
            task_code=_build_code("AI"),
            user_id=user.id,
            session_id=session_id,
            capture_id=capture_id,
            device_id=device_id,
            task_type=task_type,
            status="succeeded",
            provider_name=provider_name,
            request_payload=request_payload,
            response_payload=response_payload,
            result_summary=str(response_payload.get("summary") or "").strip() or None,
            result_score=self._to_decimal(response_payload.get("score")),
            recommended_pan_delta=self._to_decimal(response_payload.get("recommended_pan_delta")),
            recommended_tilt_delta=self._to_decimal(response_payload.get("recommended_tilt_delta")),
            target_box_norm=response_payload.get("target_box_norm"),
            finished_at=_utcnow(),
        )
        self.ai_task_repo.add(task)
        self.session.commit()
        self.session.refresh(task)
        return task

    def _create_failed_ai_task(
        self,
        *,
        user: User,
        session_id: int,
        capture_id: int | None,
        task_type: str,
        provider_name: str,
        request_payload: dict[str, Any],
        provider_metadata: dict[str, Any],
        error_message: str,
        device_id: int | None = None,
    ) -> AiTask:
        task = AiTask(
            id=_next_id(self.session, AiTask),
            task_code=_build_code("AI"),
            user_id=user.id,
            session_id=session_id,
            capture_id=capture_id,
            device_id=device_id,
            task_type=task_type,
            status="failed",
            provider_name=provider_name,
            request_payload=request_payload,
            response_payload={"provider_metadata": provider_metadata},
            error_message=error_message,
            finished_at=_utcnow(),
        )
        self.ai_task_repo.add(task)
        self.session.commit()
        self.session.refresh(task)
        return task

    def _to_decimal(self, value: Any) -> Decimal | None:
        if value is None or value == "":
            return None
        return Decimal(str(value))
