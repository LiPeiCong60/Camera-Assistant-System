"""Mobile-facing minimal business routes."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile, status
from sqlalchemy.orm import Session

from backend.app.api.dependencies import get_current_user, get_db_session
from backend.app.core.config import get_settings
from backend.app.models.user import User
from backend.app.schemas import (
    AiTaskRead,
    AnalyzeBackgroundRequest,
    AnalyzePhotoRequest,
    ApiResponse,
    LoginRequest,
    LoginResponse,
    BatchPickRequest,
    BatchPickResult,
    CaptureCreateRequest,
    CaptureRead,
    CaptureUploadRead,
    CaptureSessionCreateRequest,
    CaptureSessionRead,
    ListData,
    PlanRead,
    SubscriptionRead,
    TemplateCreateRequest,
    TemplateRead,
    UserRead,
    RegisterRequest,
)
from backend.app.services.auth_service import AuthService
from backend.app.services.mobile_service import MobileService

router = APIRouter(prefix="/mobile", tags=["mobile"])


def _build_upload_file_parts(upload: UploadFile) -> tuple[str, str]:
    original_name = Path(upload.filename or "capture.jpg").name
    suffix = Path(original_name).suffix.lower()
    if not suffix:
        content_type = (upload.content_type or "").lower()
        if content_type == "image/png":
            suffix = ".png"
        elif content_type == "image/webp":
            suffix = ".webp"
        else:
            suffix = ".jpg"
    return original_name, suffix


def _is_supported_image_upload(upload: UploadFile) -> bool:
    content_type = (upload.content_type or "").lower()
    if content_type.startswith("image/"):
        return True

    filename = Path(upload.filename or "").name.lower()
    suffix = Path(filename).suffix.lower()
    return suffix in {".jpg", ".jpeg", ".png", ".webp"}


def _store_capture_upload(request: Request, current_user: User, upload: UploadFile) -> CaptureUploadRead:
    settings = get_settings()
    original_name, suffix = _build_upload_file_parts(upload)
    date_folder = datetime.now().strftime("%Y-%m-%d")
    relative_path = Path("captures") / f"user_{current_user.id}" / date_folder / f"{uuid4().hex}{suffix}"
    storage_path = Path(settings.uploads_dir) / relative_path
    storage_path.parent.mkdir(parents=True, exist_ok=True)
    storage_path.write_bytes(upload.file.read())
    file_url = str(request.url_for("uploads", path=relative_path.as_posix()))
    return CaptureUploadRead(
        file_url=file_url,
        storage_provider="local_static",
        storage_path=str(storage_path),
        relative_path=relative_path.as_posix(),
        original_filename=original_name,
        content_type=upload.content_type,
    )


@router.post("/auth/login", response_model=ApiResponse[LoginResponse])
def mobile_login(
    payload: LoginRequest,
    session: Session = Depends(get_db_session),
) -> ApiResponse[LoginResponse]:
    data = AuthService(session).login_mobile(payload.phone, payload.password)
    return ApiResponse(data=data)


@router.post("/auth/register", response_model=ApiResponse[LoginResponse])
def mobile_register(
    payload: RegisterRequest,
    session: Session = Depends(get_db_session),
) -> ApiResponse[LoginResponse]:
    data = AuthService(session).register_mobile(payload)
    return ApiResponse(message="registered", data=data)


@router.get("/me", response_model=ApiResponse[UserRead])
def get_me(current_user: User = Depends(get_current_user)) -> ApiResponse[UserRead]:
    return ApiResponse(data=UserRead.model_validate(current_user))


@router.get("/plans", response_model=ApiResponse[ListData[PlanRead]])
def get_plans(session: Session = Depends(get_db_session)) -> ApiResponse[ListData[PlanRead]]:
    service = MobileService(session)
    items = [PlanRead.model_validate(plan) for plan in service.list_plans()]
    return ApiResponse(data=ListData(items=items))


@router.get("/subscription", response_model=ApiResponse[SubscriptionRead])
def get_subscription(
    session: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[SubscriptionRead]:
    subscription = MobileService(session).get_subscription(current_user)
    if subscription is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="subscription not found")
    return ApiResponse(data=SubscriptionRead.model_validate(subscription))


@router.post("/templates", response_model=ApiResponse[TemplateRead])
def create_template(
    payload: TemplateCreateRequest,
    session: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[TemplateRead]:
    template = MobileService(session).create_template(current_user, payload)
    return ApiResponse(data=TemplateRead.model_validate(template))


@router.get("/templates", response_model=ApiResponse[ListData[TemplateRead]])
def list_templates(
    session: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[ListData[TemplateRead]]:
    items = [TemplateRead.model_validate(item) for item in MobileService(session).list_templates(current_user)]
    return ApiResponse(data=ListData(items=items))


@router.delete("/templates/{template_id}", response_model=ApiResponse[TemplateRead])
def delete_template(
    template_id: int,
    session: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[TemplateRead]:
    template = MobileService(session).delete_template(current_user, template_id)
    return ApiResponse(message="template deleted", data=TemplateRead.model_validate(template))


@router.post("/sessions", response_model=ApiResponse[CaptureSessionRead])
def create_session(
    payload: CaptureSessionCreateRequest,
    session: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[CaptureSessionRead]:
    capture_session = MobileService(session).create_capture_session(current_user, payload)
    return ApiResponse(data=CaptureSessionRead.model_validate(capture_session))


@router.post("/captures/upload", response_model=ApiResponse[CaptureRead])
def create_capture(
    payload: CaptureCreateRequest,
    session: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[CaptureRead]:
    capture = MobileService(session).create_capture(current_user, payload)
    return ApiResponse(data=CaptureRead.model_validate(capture))


@router.post("/captures/file", response_model=ApiResponse[CaptureUploadRead])
def upload_capture_file(
    request: Request,
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[CaptureUploadRead]:
    if not _is_supported_image_upload(file):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="only image uploads are supported")
    upload_data = _store_capture_upload(request, current_user, file)
    return ApiResponse(message="capture file uploaded", data=upload_data)


@router.post("/ai/analyze-photo", response_model=ApiResponse[AiTaskRead])
def analyze_photo(
    payload: AnalyzePhotoRequest,
    session: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[AiTaskRead]:
    task = MobileService(session).create_analyze_photo_task(current_user, payload)
    return ApiResponse(data=AiTaskRead.model_validate(task))


@router.post("/ai/analyze-background", response_model=ApiResponse[AiTaskRead])
def analyze_background(
    payload: AnalyzeBackgroundRequest,
    session: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[AiTaskRead]:
    task = MobileService(session).create_analyze_background_task(current_user, payload)
    return ApiResponse(data=AiTaskRead.model_validate(task))


@router.post("/ai/batch-pick", response_model=ApiResponse[BatchPickResult])
def batch_pick(
    payload: BatchPickRequest,
    session: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[BatchPickResult]:
    task, best_capture_id = MobileService(session).create_batch_pick_task(current_user, payload)
    return ApiResponse(data=BatchPickResult(task=AiTaskRead.model_validate(task), best_capture_id=best_capture_id))


@router.get("/ai/tasks/{task_id}", response_model=ApiResponse[AiTaskRead])
def get_ai_task(
    task_id: int,
    session: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[AiTaskRead]:
    task = MobileService(session).get_ai_task(current_user, task_id)
    return ApiResponse(data=AiTaskRead.model_validate(task))


@router.get("/history/sessions", response_model=ApiResponse[ListData[CaptureSessionRead]])
def get_history_sessions(
    session: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[ListData[CaptureSessionRead]]:
    items = [CaptureSessionRead.model_validate(item) for item in MobileService(session).list_history_sessions(current_user)]
    return ApiResponse(data=ListData(items=items))


@router.get("/history/captures", response_model=ApiResponse[ListData[CaptureRead]])
def get_history_captures(
    session: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ApiResponse[ListData[CaptureRead]]:
    items = [CaptureRead.model_validate(item) for item in MobileService(session).list_history_captures(current_user)]
    return ApiResponse(data=ListData(items=items))
