"""Capture routes for device_runtime API."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel

from device_runtime.api.dependencies import require_session

router = APIRouter(prefix="/api/device/capture", tags=["device-capture"])

_CAPTURE_ROOT = Path("captures").resolve()


class TriggerCaptureRequest(BaseModel):
    reason: str = "manual"
    auto_analyze: bool = False


def _serialize_analysis(analysis) -> dict | None:
    if analysis is None:
        return None
    return {
        "score": getattr(analysis, "score", None),
        "summary": getattr(analysis, "summary", None),
        "suggestions": list(getattr(analysis, "suggestions", []) or []),
    }


def _resolve_capture_path(raw_path: str) -> Path:
    if not raw_path or not raw_path.strip():
        raise HTTPException(status_code=400, detail="capture path is required")

    candidate = Path(raw_path.strip())
    if not candidate.is_absolute():
        candidate = Path.cwd() / candidate
    candidate = candidate.resolve()

    try:
        candidate.relative_to(_CAPTURE_ROOT)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="capture path is outside capture directory") from exc

    if not candidate.is_file():
        raise HTTPException(status_code=404, detail="capture file not found")
    return candidate


def _serialize_capture_file(path: Path) -> dict:
    stat = path.stat()
    return {
        "path": str(path),
        "relative_path": str(path.relative_to(_CAPTURE_ROOT)),
        "filename": path.name,
        "size_bytes": stat.st_size,
        "modified_at": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
    }


@router.post("/trigger")
def trigger_capture(payload: TriggerCaptureRequest) -> dict:
    session = require_session()
    try:
        result = session.trigger_capture(
            reason=payload.reason,
            auto_analyze=payload.auto_analyze,
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {
        "success": True,
        "message": "capture triggered",
        "data": {
            "reason": payload.reason,
            "auto_analyze": payload.auto_analyze,
            "capture_path": result.path,
            "analysis": _serialize_analysis(result.analysis),
            "analysis_error": result.analysis_error,
        },
    }


@router.get("/list")
def list_captures(limit: int = Query(20, ge=1, le=100)) -> dict:
    _CAPTURE_ROOT.mkdir(parents=True, exist_ok=True)
    files = sorted(
        (path for path in _CAPTURE_ROOT.rglob("*.jpg") if path.is_file()),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    return {
        "success": True,
        "message": "capture files listed",
        "data": {
            "items": [_serialize_capture_file(path.resolve()) for path in files[:limit]],
        },
    }


@router.get("/file")
def get_capture_file(path: str = Query(...)) -> FileResponse:
    capture_path = _resolve_capture_path(path)
    return FileResponse(
        capture_path,
        media_type="image/jpeg",
        filename=capture_path.name,
    )
