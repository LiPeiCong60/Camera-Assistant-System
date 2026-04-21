"""Authentication service helpers."""

from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from backend.app.core.auth import create_access_token, hash_password, verify_password
from backend.app.core.config import get_settings
from backend.app.models.user import User
from backend.app.repositories.user_repository import UserRepository
from backend.app.schemas.auth import AuthUserSummary, LoginResponse, RegisterRequest


class AuthService:
    def __init__(self, session: Session) -> None:
        self.session = session
        self.user_repo = UserRepository(session)
        self.settings = get_settings()

    def login_mobile(self, phone: str, password: str) -> LoginResponse:
        user = self._authenticate(phone, password)
        if user.role != "user":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="user login required")
        return self._build_login_response(user)

    def login_admin(self, phone: str, password: str) -> LoginResponse:
        user = self._authenticate(phone, password)
        if user.role != "admin":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="admin login required")
        return self._build_login_response(user)

    def register_mobile(self, payload: RegisterRequest) -> LoginResponse:
        phone = payload.phone.strip()
        display_name = payload.display_name.strip()
        if not phone:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="phone is required")
        if not display_name:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="display_name is required")

        existing_user = self.user_repo.get_by_phone(phone)
        if existing_user is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="phone already exists")

        user = User(
            user_code=self._build_mobile_user_code(),
            phone=phone,
            password_hash=hash_password(payload.password),
            display_name=display_name,
            role="user",
            status="active",
            last_login_at=datetime.now(timezone.utc),
        )
        self.session.add(user)
        self.session.commit()
        self.session.refresh(user)
        return self._build_login_response(user)

    def _authenticate(self, phone: str, password: str) -> User:
        user = self.user_repo.get_by_phone(phone)
        if user is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid phone or password")

        if user.status != "active":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="user is not active")

        if not verify_password(password, user.password_hash):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid phone or password")

        user.last_login_at = datetime.now(timezone.utc)
        self.session.commit()
        self.session.refresh(user)
        return user

    def _build_login_response(self, user: User) -> LoginResponse:
        token = create_access_token(
            secret=self.settings.auth_secret,
            user_code=user.user_code,
            role=user.role,
            ttl_seconds=self.settings.access_token_ttl_seconds,
        )
        return LoginResponse(
            access_token=token,
            user=AuthUserSummary(
                id=user.id,
                display_name=user.display_name,
                role=user.role,
                status=user.status,
            ),
        )

    def _build_mobile_user_code(self) -> str:
        return f"USR_MOBILE_REG_{uuid4().hex[:8]}"
