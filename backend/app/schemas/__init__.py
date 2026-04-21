"""Schema exports."""

from backend.app.schemas.ai_provider_config import (
    AiProviderConfigRead,
    AiProviderConfigWriteRequest,
)
from backend.app.schemas.ai_task import (
    AiTaskRead,
    AnalyzeBackgroundRequest,
    AnalyzePhotoRequest,
    BatchPickRequest,
    BatchPickResult,
)
from backend.app.schemas.auth import AuthUserSummary, LoginRequest, LoginResponse, RegisterRequest
from backend.app.schemas.base import ApiResponse, ListData, SchemaModel
from backend.app.schemas.capture import CaptureCreateRequest, CaptureRead, CaptureUploadRead
from backend.app.schemas.capture_session import CaptureSessionCreateRequest, CaptureSessionRead
from backend.app.schemas.device import DeviceRead, DeviceWriteRequest
from backend.app.schemas.plan import PlanRead, PlanWriteRequest
from backend.app.schemas.statistics import OverviewStatisticsRead
from backend.app.schemas.subscription import SubscriptionRead
from backend.app.schemas.template import RecommendedTemplateWriteRequest, TemplateCreateRequest, TemplateRead
from backend.app.schemas.user import UserCreateRequest, UserRead, UserUpdateRequest

__all__ = [
    "AiTaskRead",
    "AiProviderConfigRead",
    "AiProviderConfigWriteRequest",
    "AnalyzeBackgroundRequest",
    "AnalyzePhotoRequest",
    "ApiResponse",
    "AuthUserSummary",
    "BatchPickRequest",
    "BatchPickResult",
    "CaptureCreateRequest",
    "CaptureRead",
    "CaptureUploadRead",
    "CaptureSessionCreateRequest",
    "CaptureSessionRead",
    "DeviceRead",
    "DeviceWriteRequest",
    "ListData",
    "LoginRequest",
    "LoginResponse",
    "OverviewStatisticsRead",
    "PlanRead",
    "PlanWriteRequest",
    "RegisterRequest",
    "RecommendedTemplateWriteRequest",
    "SchemaModel",
    "SubscriptionRead",
    "TemplateCreateRequest",
    "TemplateRead",
    "UserCreateRequest",
    "UserRead",
    "UserUpdateRequest",
]
