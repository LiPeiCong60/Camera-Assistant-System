"""Shared API dependencies."""

from __future__ import annotations

from collections.abc import Generator

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy.orm import Session

from backend.app.core.auth import decode_access_token
from backend.app.core.config import get_settings
from backend.app.core.db import get_session_factory
from backend.app.models.user import User
from backend.app.repositories.user_repository import UserRepository


def get_db_session() -> Generator[Session, None, None]:
    settings = get_settings()
    session_factory = get_session_factory(settings.database_url)
    if session_factory is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="database is not configured",
        )

    with session_factory() as session:
        yield session


def get_current_user(
    session: Session = Depends(get_db_session),
    authorization: str | None = Header(default=None, alias="Authorization"),
    x_user_code: str | None = Header(default=None, alias="X-User-Code"),
) -> User:
    user = _resolve_user_from_auth(session, authorization=authorization, fallback_user_code=x_user_code)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="user not found")

    return user


def get_current_admin(
    session: Session = Depends(get_db_session),
    authorization: str | None = Header(default=None, alias="Authorization"),
) -> User:
    admin_user = _resolve_user_from_auth(session, authorization=authorization, fallback_user_code=None)
    if admin_user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="admin user not found")

    if admin_user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="admin access required")

    return admin_user


def _resolve_user_from_auth(
    session: Session,
    *,
    authorization: str | None,
    fallback_user_code: str | None,
) -> User | None:
    user_repo = UserRepository(session)
    if authorization:
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() != "bearer" or not token:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid authorization header")

        try:
            payload = decode_access_token(token, secret=get_settings().auth_secret)
        except ValueError as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc)) from exc

        user_code = payload.get("user_code")
        if not user_code:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid token payload")

        return user_repo.get_by_user_code(user_code)

    if not fallback_user_code:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="authorization is required")

    return user_repo.get_by_user_code(fallback_user_code)
