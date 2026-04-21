"""Admin-facing minimal read routes."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from backend.app.api.dependencies import get_current_admin, get_db_session
from backend.app.models.ai_provider_config import AiProviderConfig
from backend.app.models.user import User
from backend.app.schemas import (
    AiProviderConfigRead,
    AiProviderConfigWriteRequest,
    AiTaskRead,
    ApiResponse,
    CaptureRead,
    DeviceRead,
    DeviceWriteRequest,
    ListData,
    LoginRequest,
    LoginResponse,
    OverviewStatisticsRead,
    PlanRead,
    PlanWriteRequest,
    RecommendedTemplateWriteRequest,
    TemplateRead,
    UserCreateRequest,
    UserRead,
    UserUpdateRequest,
)
from backend.app.services.auth_service import AuthService
from backend.app.services.admin_service import AdminService

router = APIRouter(prefix="/admin", tags=["admin"])


def _mask_api_key(api_key: str | None) -> str | None:
    if not api_key:
        return None
    if len(api_key) <= 6:
        return "*" * len(api_key)
    return f"{api_key[:3]}***{api_key[-2:]}"


def _build_ai_provider_read(config: AiProviderConfig | None) -> AiProviderConfigRead:
    if config is None:
        return AiProviderConfigRead(
            id=0,
            provider_code="mock_ai",
            vendor_name="mock",
            provider_format="openai_compatible",
            display_name="Mock AI",
            api_base_url=None,
            model_name=None,
            enabled=False,
            is_default=True,
            has_api_key=False,
            masked_api_key=None,
            notes=None,
            extra_config={},
        )
    return AiProviderConfigRead(
        id=config.id,
        provider_code=config.provider_code,
        vendor_name=config.vendor_name,
        provider_format=config.provider_format,
        display_name=config.display_name,
        api_base_url=config.api_base_url,
        model_name=config.model_name,
        enabled=config.enabled,
        is_default=config.is_default,
        has_api_key=bool(config.api_key),
        masked_api_key=_mask_api_key(config.api_key),
        notes=config.notes,
        extra_config=config.extra_config,
    )


@router.post("/login", response_model=ApiResponse[LoginResponse])
def admin_login(
    payload: LoginRequest,
    session: Session = Depends(get_db_session),
) -> ApiResponse[LoginResponse]:
    data = AuthService(session).login_admin(payload.phone, payload.password)
    return ApiResponse(data=data)


@router.get("/users", response_model=ApiResponse[ListData[UserRead]])
def list_users(
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[ListData[UserRead]]:
    items = AdminService(session).list_user_reads()
    return ApiResponse(data=ListData(items=items))


@router.get("/users/{user_id}", response_model=ApiResponse[UserRead])
def get_user_detail(
    user_id: int,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[UserRead]:
    user = AdminService(session).get_user_read(user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="user not found")
    return ApiResponse(data=user)


@router.post("/users", response_model=ApiResponse[UserRead])
def create_user(
    payload: UserCreateRequest,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[UserRead]:
    service = AdminService(session)
    user = service.create_user(payload)
    return ApiResponse(data=service.get_user_read(user.id))


@router.put("/users/{user_id}", response_model=ApiResponse[UserRead])
def update_user(
    user_id: int,
    payload: UserUpdateRequest,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[UserRead]:
    service = AdminService(session)
    user = service.update_user(user_id, payload)
    return ApiResponse(data=service.get_user_read(user.id))


@router.delete("/users/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(
    user_id: int,
    current_admin: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> Response:
    AdminService(session).delete_user(user_id, current_admin.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/plans", response_model=ApiResponse[ListData[PlanRead]])
def list_plans(
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[ListData[PlanRead]]:
    items = [PlanRead.model_validate(item) for item in AdminService(session).list_plans()]
    return ApiResponse(data=ListData(items=items))


@router.post("/plans", response_model=ApiResponse[PlanRead])
def create_plan(
    payload: PlanWriteRequest,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[PlanRead]:
    plan = AdminService(session).create_plan(payload)
    return ApiResponse(data=PlanRead.model_validate(plan))


@router.put("/plans/{plan_id}", response_model=ApiResponse[PlanRead])
def update_plan(
    plan_id: int,
    payload: PlanWriteRequest,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[PlanRead]:
    plan = AdminService(session).update_plan(plan_id, payload)
    return ApiResponse(data=PlanRead.model_validate(plan))


@router.delete("/plans/{plan_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_plan(
    plan_id: int,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> Response:
    AdminService(session).delete_plan(plan_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/templates/recommended", response_model=ApiResponse[ListData[TemplateRead]])
def list_recommended_templates(
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[ListData[TemplateRead]]:
    items = [TemplateRead.model_validate(item) for item in AdminService(session).list_recommended_templates()]
    return ApiResponse(data=ListData(items=items))


@router.post("/templates/recommended", response_model=ApiResponse[TemplateRead])
def create_recommended_template(
    payload: RecommendedTemplateWriteRequest,
    current_admin: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[TemplateRead]:
    template = AdminService(session).create_recommended_template(current_admin, payload)
    return ApiResponse(data=TemplateRead.model_validate(template))


@router.put("/templates/recommended/{template_id}", response_model=ApiResponse[TemplateRead])
def update_recommended_template(
    template_id: int,
    payload: RecommendedTemplateWriteRequest,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[TemplateRead]:
    template = AdminService(session).update_recommended_template(template_id, payload)
    return ApiResponse(data=TemplateRead.model_validate(template))


@router.delete("/templates/recommended/{template_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_recommended_template(
    template_id: int,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> Response:
    AdminService(session).delete_recommended_template(template_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/devices", response_model=ApiResponse[ListData[DeviceRead]])
def list_devices(
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[ListData[DeviceRead]]:
    items = [DeviceRead.model_validate(item) for item in AdminService(session).list_devices()]
    return ApiResponse(data=ListData(items=items))


@router.post("/devices", response_model=ApiResponse[DeviceRead])
def create_device(
    payload: DeviceWriteRequest,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[DeviceRead]:
    device = AdminService(session).create_device(payload)
    return ApiResponse(data=DeviceRead.model_validate(device))


@router.put("/devices/{device_id}", response_model=ApiResponse[DeviceRead])
def update_device(
    device_id: int,
    payload: DeviceWriteRequest,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[DeviceRead]:
    device = AdminService(session).update_device(device_id, payload)
    return ApiResponse(data=DeviceRead.model_validate(device))


@router.delete("/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_device(
    device_id: int,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> Response:
    AdminService(session).delete_device(device_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/captures", response_model=ApiResponse[ListData[CaptureRead]])
def list_captures(
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[ListData[CaptureRead]]:
    items = [CaptureRead.model_validate(item) for item in AdminService(session).list_captures()]
    return ApiResponse(data=ListData(items=items))


@router.get("/ai/tasks", response_model=ApiResponse[ListData[AiTaskRead]])
def list_ai_tasks(
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[ListData[AiTaskRead]]:
    items = [AiTaskRead.model_validate(item) for item in AdminService(session).list_ai_tasks()]
    return ApiResponse(data=ListData(items=items))


@router.get("/statistics/overview", response_model=ApiResponse[OverviewStatisticsRead])
def get_statistics_overview(
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[OverviewStatisticsRead]:
    data = AdminService(session).get_overview_statistics()
    return ApiResponse(data=data)


@router.get("/ai/provider-config", response_model=ApiResponse[AiProviderConfigRead])
def get_ai_provider_config(
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[AiProviderConfigRead]:
    config = AdminService(session).get_ai_provider_config()
    return ApiResponse(data=_build_ai_provider_read(config))


@router.get("/ai/provider-configs", response_model=ApiResponse[ListData[AiProviderConfigRead]])
def list_ai_provider_configs(
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[ListData[AiProviderConfigRead]]:
    items = [_build_ai_provider_read(item) for item in AdminService(session).list_ai_provider_configs()]
    return ApiResponse(data=ListData(items=items))


@router.post("/ai/provider-configs", response_model=ApiResponse[AiProviderConfigRead])
def create_ai_provider_config(
    payload: AiProviderConfigWriteRequest,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[AiProviderConfigRead]:
    config = AdminService(session).create_ai_provider_config(payload)
    return ApiResponse(data=_build_ai_provider_read(config))


@router.put("/ai/provider-configs/{config_id}", response_model=ApiResponse[AiProviderConfigRead])
def update_ai_provider_config(
    config_id: int,
    payload: AiProviderConfigWriteRequest,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[AiProviderConfigRead]:
    config = AdminService(session).update_ai_provider_config(config_id, payload)
    return ApiResponse(data=_build_ai_provider_read(config))


@router.delete("/ai/provider-configs/{config_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_ai_provider_config(
    config_id: int,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> Response:
    AdminService(session).delete_ai_provider_config(config_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put("/ai/provider-config", response_model=ApiResponse[AiProviderConfigRead])
def upsert_ai_provider_config(
    payload: AiProviderConfigWriteRequest,
    _: User = Depends(get_current_admin),
    session: Session = Depends(get_db_session),
) -> ApiResponse[AiProviderConfigRead]:
    config = AdminService(session).upsert_ai_provider_config(payload)
    return ApiResponse(data=_build_ai_provider_read(config))
