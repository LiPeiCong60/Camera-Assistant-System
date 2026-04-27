"""Admin-facing management service helpers."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from backend.app.models.ai_task import AiTask
from backend.app.models.ai_provider_config import AiProviderConfig
from backend.app.models.capture import Capture
from backend.app.models.capture_session import CaptureSession
from backend.app.models.device import Device
from backend.app.models.plan import Plan
from backend.app.models.template import Template
from backend.app.models.user import User
from backend.app.models.user_subscription import UserSubscription
from backend.app.core.auth import hash_password
from backend.app.repositories.ai_provider_config_repository import AiProviderConfigRepository
from backend.app.repositories.ai_task_repository import AiTaskRepository
from backend.app.repositories.capture_repository import CaptureRepository
from backend.app.repositories.device_repository import DeviceRepository
from backend.app.repositories.plan_repository import PlanRepository
from backend.app.repositories.template_repository import TemplateRepository
from backend.app.repositories.user_repository import UserRepository
from backend.app.repositories.user_subscription_repository import UserSubscriptionRepository
from backend.app.schemas.ai_provider_config import AiProviderConfigWriteRequest
from backend.app.schemas.device import DeviceWriteRequest
from backend.app.schemas.plan import PlanWriteRequest
from backend.app.schemas.statistics import OverviewStatisticsRead
from backend.app.schemas.template import RecommendedTemplateWriteRequest
from backend.app.schemas.user import UserCreateRequest, UserRead, UserUpdateRequest
from backend.app.services.template_pose_service import TemplatePoseService


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class AdminService:
    TEST_USER_CODE_PREFIXES = ("USR_TEST_", "USR_STAGE", "USR_MOBILE_REG_")

    def __init__(self, session: Session) -> None:
        self.session = session
        self.ai_provider_config_repo = AiProviderConfigRepository(session)
        self.user_repo = UserRepository(session)
        self.plan_repo = PlanRepository(session)
        self.subscription_repo = UserSubscriptionRepository(session)
        self.device_repo = DeviceRepository(session)
        self.template_repo = TemplateRepository(session)
        self.capture_repo = CaptureRepository(session)
        self.ai_task_repo = AiTaskRepository(session)

    def list_users(self):
        return self.user_repo.list_users()

    def list_user_reads(self) -> list[UserRead]:
        users = self.user_repo.list_users()
        subscription_map = self.subscription_repo.get_current_for_users([int(item.id) for item in users])
        return [self._build_user_read(item, subscription_map.get(int(item.id))) for item in users]

    def get_user(self, user_id: int):
        return self.user_repo.get(user_id)

    def get_user_read(self, user_id: int) -> UserRead | None:
        user = self.user_repo.get(user_id)
        if user is None:
            return None
        subscription = self.subscription_repo.get_current_for_user(user_id)
        return self._build_user_read(user, subscription)

    def create_user(self, payload: UserCreateRequest) -> User:
        self._ensure_unique_user_fields(
            user_code=payload.user_code,
            phone=payload.phone,
            email=payload.email,
        )
        user = User(
            user_code=payload.user_code,
            phone=self._normalize_optional_text(payload.phone),
            email=self._normalize_optional_text(payload.email),
            password_hash=hash_password(payload.password),
            display_name=payload.display_name.strip(),
            avatar_url=self._normalize_optional_text(payload.avatar_url),
            role=payload.role,
            status=payload.status,
        )
        self.session.add(user)
        self.session.flush()
        self._replace_current_subscription(user.id, payload.current_plan_id)
        self.session.commit()
        self.session.refresh(user)
        return user

    def update_user(self, user_id: int, payload: UserUpdateRequest) -> User:
        user = self.user_repo.get(user_id)
        if user is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="user not found")

        self._ensure_unique_user_fields(
            user_code=payload.user_code,
            phone=payload.phone,
            email=payload.email,
            exclude_user_id=user_id,
        )
        user.user_code = payload.user_code
        user.phone = self._normalize_optional_text(payload.phone)
        user.email = self._normalize_optional_text(payload.email)
        user.display_name = payload.display_name.strip()
        user.avatar_url = self._normalize_optional_text(payload.avatar_url)
        user.role = payload.role
        user.status = payload.status
        if payload.password:
            user.password_hash = hash_password(payload.password)
        self._replace_current_subscription(user.id, payload.current_plan_id)
        self.session.commit()
        self.session.refresh(user)
        return user

    def delete_user(self, user_id: int, current_admin_id: int) -> None:
        if user_id == current_admin_id:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="cannot delete current admin")

        user = self.user_repo.get(user_id)
        if user is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="user not found")

        related_items = {
            "subscriptions": int(
                self.session.scalar(
                    select(func.count()).select_from(UserSubscription).where(UserSubscription.user_id == user_id)
                )
                or 0
            ),
            "devices": int(
                self.session.scalar(select(func.count()).select_from(Device).where(Device.user_id == user_id)) or 0
            ),
            "templates": int(
                self.session.scalar(select(func.count()).select_from(Template).where(Template.user_id == user_id)) or 0
            ),
            "sessions": int(
                self.session.scalar(
                    select(func.count()).select_from(CaptureSession).where(CaptureSession.user_id == user_id)
                )
                or 0
            ),
            "captures": int(
                self.session.scalar(select(func.count()).select_from(Capture).where(Capture.user_id == user_id)) or 0
            ),
            "ai_tasks": int(
                self.session.scalar(select(func.count()).select_from(AiTask).where(AiTask.user_id == user_id)) or 0
            ),
        }
        has_related_data = any(count > 0 for count in related_items.values())
        if has_related_data:
            self._delete_user_related_data(user_id)

        self.session.delete(user)
        self.session.commit()

    def list_plans(self):
        return self.plan_repo.list_all_plans()

    def create_plan(self, payload: PlanWriteRequest) -> Plan:
        existing = self.plan_repo.get_by_plan_code(payload.plan_code)
        if existing is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="plan_code already exists")

        plan = Plan(
            plan_code=payload.plan_code,
            name=payload.name,
            description=payload.description,
            price_cents=payload.price_cents,
            currency=payload.currency,
            billing_cycle_days=payload.billing_cycle_days,
            capture_quota=payload.capture_quota,
            ai_task_quota=payload.ai_task_quota,
            feature_flags=payload.feature_flags,
            status=payload.status,
        )
        self.session.add(plan)
        self.session.commit()
        self.session.refresh(plan)
        return plan

    def update_plan(self, plan_id: int, payload: PlanWriteRequest) -> Plan:
        plan = self.plan_repo.get(plan_id)
        if plan is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="plan not found")

        existing = self.plan_repo.get_by_plan_code(payload.plan_code)
        if existing is not None and existing.id != plan_id:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="plan_code already exists")

        plan.plan_code = payload.plan_code
        plan.name = payload.name
        plan.description = payload.description
        plan.price_cents = payload.price_cents
        plan.currency = payload.currency
        plan.billing_cycle_days = payload.billing_cycle_days
        plan.capture_quota = payload.capture_quota
        plan.ai_task_quota = payload.ai_task_quota
        plan.feature_flags = payload.feature_flags
        plan.status = payload.status
        self.session.commit()
        self.session.refresh(plan)
        return plan

    def delete_plan(self, plan_id: int) -> None:
        plan = self.plan_repo.get(plan_id)
        if plan is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="plan not found")

        if self.plan_repo.has_active_subscriptions(plan_id):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="plan has active subscriptions and cannot be deleted",
            )

        self.plan_repo.delete_inactive_subscriptions(plan_id)
        self.session.delete(plan)
        self.session.commit()

    def list_devices(self):
        return self.device_repo.list_all_devices()

    def list_recommended_templates(self) -> list[Template]:
        return self.template_repo.list_recommended_defaults()

    def create_recommended_template(
        self,
        current_admin: User,
        payload: RecommendedTemplateWriteRequest,
    ) -> Template:
        template_data = self._resolve_recommended_template_data(payload)
        source_image_url = self._normalize_optional_text(payload.source_image_url)
        preview_image_url = self._normalize_optional_text(payload.preview_image_url) or source_image_url
        template = Template(
            user_id=current_admin.id,
            name=payload.name.strip(),
            template_type=payload.template_type,
            source_image_url=source_image_url,
            preview_image_url=preview_image_url,
            template_data=template_data,
            is_recommended_default=True,
            recommended_sort_order=payload.recommended_sort_order,
            status=payload.status,
        )
        self.session.add(template)
        self.session.commit()
        self.session.refresh(template)
        return template

    def update_recommended_template(
        self,
        template_id: int,
        payload: RecommendedTemplateWriteRequest,
    ) -> Template:
        template = self.template_repo.get_recommended_default(template_id)
        if template is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="recommended template not found")

        template_data = self._resolve_recommended_template_data(payload)
        source_image_url = self._normalize_optional_text(payload.source_image_url)
        preview_image_url = self._normalize_optional_text(payload.preview_image_url) or source_image_url
        template.name = payload.name.strip()
        template.template_type = payload.template_type
        template.source_image_url = source_image_url
        template.preview_image_url = preview_image_url
        template.template_data = template_data
        template.is_recommended_default = True
        template.recommended_sort_order = payload.recommended_sort_order
        template.status = payload.status
        self.session.commit()
        self.session.refresh(template)
        return template

    def _resolve_recommended_template_data(
        self,
        payload: RecommendedTemplateWriteRequest,
    ) -> dict:
        if payload.template_data:
            return payload.template_data

        source_image_url = self._normalize_optional_text(payload.source_image_url)
        if not source_image_url:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="template_data or source_image_url is required",
            )

        return TemplatePoseService().create_template_data(
            name=payload.name.strip(),
            source_image_url=source_image_url,
        )

    def delete_recommended_template(self, template_id: int) -> None:
        template = self.template_repo.get_recommended_default(template_id)
        if template is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="recommended template not found")

        template.status = "deleted"
        self.session.commit()

    def create_device(self, payload: DeviceWriteRequest) -> Device:
        self._ensure_user_exists(payload.user_id)
        existing = self.device_repo.get_by_device_code(payload.device_code)
        if existing is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="device_code already exists")

        device = Device(
            user_id=payload.user_id,
            device_code=payload.device_code,
            device_name=payload.device_name.strip(),
            device_type=payload.device_type,
            serial_number=self._normalize_optional_text(payload.serial_number),
            local_ip=self._normalize_optional_text(payload.local_ip),
            control_base_url=self._normalize_optional_text(payload.control_base_url),
            firmware_version=self._normalize_optional_text(payload.firmware_version),
            status=payload.status,
            is_online=payload.is_online,
        )
        self.session.add(device)
        self.session.commit()
        self.session.refresh(device)
        return device

    def update_device(self, device_id: int, payload: DeviceWriteRequest) -> Device:
        device = self.device_repo.get(device_id)
        if device is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="device not found")

        self._ensure_user_exists(payload.user_id)
        existing = self.device_repo.get_by_device_code(payload.device_code)
        if existing is not None and existing.id != device_id:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="device_code already exists")

        device.user_id = payload.user_id
        device.device_code = payload.device_code
        device.device_name = payload.device_name.strip()
        device.device_type = payload.device_type
        device.serial_number = self._normalize_optional_text(payload.serial_number)
        device.local_ip = self._normalize_optional_text(payload.local_ip)
        device.control_base_url = self._normalize_optional_text(payload.control_base_url)
        device.firmware_version = self._normalize_optional_text(payload.firmware_version)
        device.status = payload.status
        device.is_online = payload.is_online
        self.session.commit()
        self.session.refresh(device)
        return device

    def delete_device(self, device_id: int) -> None:
        device = self.device_repo.get(device_id)
        if device is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="device not found")

        self.session.delete(device)
        self.session.commit()

    def list_captures(self):
        return self.capture_repo.list_all_captures()

    def delete_capture(self, capture_id: int) -> None:
        capture = self.capture_repo.get(capture_id)
        if capture is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="capture not found")

        self.session.execute(delete(AiTask).where(AiTask.capture_id == capture_id))
        self.session.delete(capture)
        self.session.commit()

    def delete_all_captures(self) -> int:
        ai_task_result = self.session.execute(delete(AiTask).where(AiTask.capture_id.is_not(None)))
        capture_result = self.session.execute(delete(Capture))
        self.session.execute(delete(CaptureSession))
        self.session.commit()
        return int(capture_result.rowcount or 0) + int(ai_task_result.rowcount or 0)

    def list_ai_tasks(self):
        return self.ai_task_repo.list_all_tasks()

    def delete_ai_task(self, task_id: int) -> None:
        ai_task = self.ai_task_repo.get(task_id)
        if ai_task is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ai task not found")

        self.session.delete(ai_task)
        self.session.commit()

    def delete_all_ai_tasks(self) -> int:
        result = self.session.execute(delete(AiTask))
        self.session.commit()
        return int(result.rowcount or 0)

    def list_ai_provider_configs(self) -> list[AiProviderConfig]:
        return self.ai_provider_config_repo.list_all()

    def get_ai_provider_config(self) -> AiProviderConfig | None:
        return self.ai_provider_config_repo.get_default()

    def create_ai_provider_config(self, payload: AiProviderConfigWriteRequest) -> AiProviderConfig:
        config = self.ai_provider_config_repo.get_by_provider_code(payload.provider_code)
        if config is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="provider_code already exists")

        config = AiProviderConfig(
            provider_code=payload.provider_code,
            vendor_name=payload.vendor_name,
            provider_format=payload.provider_format,
            display_name=payload.display_name,
            api_base_url=payload.api_base_url,
            api_key=payload.api_key,
            model_name=payload.model_name,
            enabled=payload.enabled,
            is_default=payload.is_default,
            notes=payload.notes,
            extra_config=payload.extra_config,
        )
        self._apply_default_selection(config, payload.is_default)
        self.session.add(config)
        self.session.commit()
        self._ensure_default_exists()
        self.session.refresh(config)
        return config

    def update_ai_provider_config(self, config_id: int, payload: AiProviderConfigWriteRequest) -> AiProviderConfig:
        config = self.ai_provider_config_repo.get(config_id)
        if config is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ai provider config not found")

        existing = self.ai_provider_config_repo.get_by_provider_code(payload.provider_code)
        if existing is not None and existing.id != config_id:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="provider_code already exists")

        config.provider_code = payload.provider_code
        config.vendor_name = payload.vendor_name
        config.provider_format = payload.provider_format
        config.display_name = payload.display_name
        config.api_base_url = payload.api_base_url
        if payload.api_key is not None:
            config.api_key = payload.api_key or None
        config.model_name = payload.model_name
        config.enabled = payload.enabled
        config.is_default = payload.is_default
        config.notes = payload.notes
        config.extra_config = payload.extra_config
        self._apply_default_selection(config, payload.is_default)
        self.session.commit()
        self._ensure_default_exists()
        self.session.refresh(config)
        return config

    def delete_ai_provider_config(self, config_id: int) -> None:
        config = self.ai_provider_config_repo.get(config_id)
        if config is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ai provider config not found")

        was_default = config.is_default
        self.session.delete(config)
        self.session.commit()

        if was_default:
            self._ensure_default_exists()

    def upsert_ai_provider_config(self, payload: AiProviderConfigWriteRequest) -> AiProviderConfig:
        config = self.ai_provider_config_repo.get_by_provider_code(payload.provider_code)
        if config is None:
            return self.create_ai_provider_config(payload)
        return self.update_ai_provider_config(config.id, payload)

    def _apply_default_selection(self, current: AiProviderConfig, should_be_default: bool) -> None:
        if not should_be_default:
            return

        stmt = select(AiProviderConfig).where(AiProviderConfig.id != current.id)
        for item in self.session.scalars(stmt):
            item.is_default = False

    def _ensure_default_exists(self) -> None:
        current_default = self.session.scalar(
            select(AiProviderConfig).where(AiProviderConfig.is_default.is_(True)).limit(1)
        )
        if current_default is not None:
            return

        fallback = self.session.scalar(
            select(AiProviderConfig)
            .order_by(AiProviderConfig.enabled.desc(), AiProviderConfig.id.asc())
            .limit(1)
        )
        if fallback is None:
            return

        fallback.is_default = True
        self.session.commit()

    def get_overview_statistics(self) -> OverviewStatisticsRead:
        return OverviewStatisticsRead(
            user_count=int(self.session.scalar(select(func.count()).select_from(User)) or 0),
            plan_count=int(self.session.scalar(select(func.count()).select_from(Plan)) or 0),
            capture_count=int(self.session.scalar(select(func.count()).select_from(Capture)) or 0),
            ai_task_count=int(self.session.scalar(select(func.count()).select_from(AiTask)) or 0),
        )

    def _build_user_read(
        self,
        user: User,
        subscription: UserSubscription | None,
    ) -> UserRead:
        plan = subscription.plan if subscription is not None else None
        return UserRead(
            id=user.id,
            user_code=user.user_code,
            phone=user.phone,
            email=user.email,
            display_name=user.display_name,
            avatar_url=user.avatar_url,
            role=user.role,
            status=user.status,
            current_plan_id=plan.id if plan is not None else None,
            current_plan_code=plan.plan_code if plan is not None else None,
            current_plan_name=plan.name if plan is not None else None,
            current_subscription_status=subscription.status if subscription is not None else None,
            current_subscription_expires_at=subscription.expires_at if subscription is not None else None,
            last_login_at=user.last_login_at,
            created_at=user.created_at,
            updated_at=user.updated_at,
        )

    def _replace_current_subscription(self, user_id: int, plan_id: int | None) -> None:
        current = self.subscription_repo.get_current_for_user(user_id)
        if plan_id is None:
            if current is not None:
                current.status = "cancelled"
                current.auto_renew = False
                current.expires_at = _utcnow()
                self.session.flush()
            return

        plan = self.plan_repo.get(plan_id)
        if plan is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="plan not found")

        started_at = _utcnow()
        expires_at = started_at + timedelta(days=plan.billing_cycle_days)
        quota_snapshot = self._build_quota_snapshot(plan)

        if current is None:
            current = UserSubscription(
                user_id=user_id,
                plan_id=plan.id,
                status="active",
                started_at=started_at,
                expires_at=expires_at,
                auto_renew=False,
                quota_snapshot=quota_snapshot,
            )
            self.session.add(current)
            self.session.flush()
            return

        current.plan_id = plan.id
        current.status = "active"
        current.started_at = started_at
        current.expires_at = expires_at
        current.auto_renew = False
        current.quota_snapshot = quota_snapshot
        self.session.flush()

    def _build_quota_snapshot(self, plan: Plan) -> dict[str, object]:
        return {
            "capture_quota": plan.capture_quota,
            "ai_task_quota": plan.ai_task_quota,
            "feature_flags": plan.feature_flags or {},
            "plan_code": plan.plan_code,
            "plan_name": plan.name,
            "billing_cycle_days": plan.billing_cycle_days,
        }

    def _ensure_user_exists(self, user_id: int) -> User:
        user = self.user_repo.get(user_id)
        if user is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="user not found")
        return user

    def _ensure_unique_user_fields(
        self,
        *,
        user_code: str,
        phone: str | None,
        email: str | None,
        exclude_user_id: int | None = None,
    ) -> None:
        existing_user_code = self.user_repo.get_by_user_code(user_code)
        if existing_user_code is not None and existing_user_code.id != exclude_user_id:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="user_code already exists")

        normalized_phone = self._normalize_optional_text(phone)
        if normalized_phone:
            existing_phone = self.user_repo.get_by_phone(normalized_phone)
            if existing_phone is not None and existing_phone.id != exclude_user_id:
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="phone already exists")

        normalized_email = self._normalize_optional_text(email)
        if normalized_email:
            existing_email = self.user_repo.get_by_email(normalized_email)
            if existing_email is not None and existing_email.id != exclude_user_id:
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="email already exists")

    def _normalize_optional_text(self, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None

    def _delete_user_related_data(self, user_id: int) -> None:
        self.session.execute(delete(AiTask).where(AiTask.user_id == user_id))
        self.session.execute(delete(Capture).where(Capture.user_id == user_id))
        self.session.execute(delete(CaptureSession).where(CaptureSession.user_id == user_id))
        self.session.execute(delete(Template).where(Template.user_id == user_id))
        self.session.execute(delete(Device).where(Device.user_id == user_id))
        self.session.execute(delete(UserSubscription).where(UserSubscription.user_id == user_id))
        self.session.flush()
