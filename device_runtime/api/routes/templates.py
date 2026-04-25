"""Template selection routes for device_runtime API."""

from __future__ import annotations

import os
import tempfile
from typing import Any

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field

from device_runtime.api.session_manager import session_manager

router = APIRouter(prefix="/api/device/templates", tags=["device-templates"])


class SelectTemplateRequest(BaseModel):
    template_id: str | int = Field(...)
    template_data: dict[str, Any] | None = None


class ImportTemplateRequest(BaseModel):
    image_path: str = Field(..., min_length=1)
    name: str | None = None


def _serialize_profile(profile) -> dict[str, Any]:
    return {
        "template_id": profile.template_id,
        "name": profile.name,
        "image_path": profile.image_path,
        "created_at": profile.created_at,
        "bbox_norm": list(profile.bbox_norm),
        "pose_point_count": len(profile.pose_points_image or {}),
    }


@router.get("")
def list_templates() -> dict:
    profiles = session_manager.list_templates()
    default_selected_template_id = session_manager.get_default_selected_template_id()
    return {
        "success": True,
        "message": "template list loaded",
        "data": {
            "items": [
                {
                    **_serialize_profile(profile),
                    "selected": profile.template_id == default_selected_template_id,
                }
                for profile in profiles
            ],
            "selected_template_id": default_selected_template_id,
            "count": len(profiles),
        },
    }


@router.post("/import")
def import_template(payload: ImportTemplateRequest) -> dict:
    try:
        profile = session_manager.import_template(payload.image_path, name=payload.name)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return {
        "success": True,
        "message": "template imported",
        "data": _serialize_profile(profile),
    }


@router.post("/upload")
async def upload_template(
    file: UploadFile = File(...),
    name: str | None = Form(None),
    select_after_import: bool = Form(True),
) -> dict:
    suffix = os.path.splitext(file.filename or "")[1] or ".jpg"
    tmp_path = None
    try:
        raw = await file.read()
        if not raw:
            raise ValueError("uploaded template image is empty")
        with tempfile.NamedTemporaryFile(prefix="template_upload_", suffix=suffix, delete=False) as tmp:
            tmp_path = tmp.name
            tmp.write(raw)

        template_name = name or os.path.splitext(file.filename or "template")[0]
        profile = session_manager.import_template(tmp_path, name=template_name)
        if select_after_import:
            session_manager.select_template(profile.template_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass

    return {
        "success": True,
        "message": "template uploaded and imported",
        "data": {
            **_serialize_profile(profile),
            "selected_for_next_session": select_after_import,
        },
    }


@router.delete("/{template_id}")
def delete_template(template_id: str) -> dict:
    removed = session_manager.delete_template(template_id)
    if not removed:
        raise HTTPException(status_code=404, detail=f"template not found: {template_id}")

    return {
        "success": True,
        "message": "template deleted",
        "data": {"template_id": template_id},
    }


@router.post("/clear")
def clear_template_selection() -> dict:
    session_manager.clear_selected_template()
    return {
        "success": True,
        "message": "template selection cleared",
        "data": {
            "selected_template_id": None,
            "selected_for_next_session": False,
        },
    }


@router.post("/select")
def select_template(payload: SelectTemplateRequest) -> dict:
    try:
        profile = session_manager.select_template(
            template_id=payload.template_id,
            template_data=payload.template_data,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {
        "success": True,
        "message": "template selected",
        "data": {
            "template_id": payload.template_id,
            "template_name": profile.name,
            "has_template_data": payload.template_data is not None,
            "selected_for_next_session": True,
        },
    }
