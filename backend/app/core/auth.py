"""Minimal password hashing and token signing helpers."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
from datetime import datetime, timedelta, timezone


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(data: str) -> bytes:
    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + padding)


def hash_password(password: str, *, iterations: int = 120000) -> str:
    salt = secrets.token_hex(16)
    derived = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), iterations)
    return f"pbkdf2_sha256${iterations}${salt}${_b64url_encode(derived)}"


def verify_password(password: str, password_hash: str | None) -> bool:
    if not password_hash:
        return False

    try:
        algorithm, iteration_text, salt, encoded_hash = password_hash.split("$", 3)
    except ValueError:
        return hmac.compare_digest(password_hash, password)

    if algorithm != "pbkdf2_sha256":
        return hmac.compare_digest(password_hash, password)

    derived = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        int(iteration_text),
    )
    return hmac.compare_digest(_b64url_encode(derived), encoded_hash)


def create_access_token(*, secret: str, user_code: str, role: str, ttl_seconds: int) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "user_code": user_code,
        "role": role,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=ttl_seconds)).timestamp()),
    }
    payload_text = json.dumps(payload, separators=(",", ":"), sort_keys=True)
    payload_part = _b64url_encode(payload_text.encode("utf-8"))
    signature = hmac.new(secret.encode("utf-8"), payload_part.encode("ascii"), hashlib.sha256).digest()
    return f"{payload_part}.{_b64url_encode(signature)}"


def decode_access_token(token: str, *, secret: str) -> dict:
    try:
        payload_part, signature_part = token.split(".", 1)
    except ValueError as exc:
        raise ValueError("invalid token format") from exc

    expected_signature = hmac.new(secret.encode("utf-8"), payload_part.encode("ascii"), hashlib.sha256).digest()
    try:
        actual_signature = _b64url_decode(signature_part)
    except Exception as exc:
        raise ValueError("invalid token signature") from exc
    if not hmac.compare_digest(expected_signature, actual_signature):
        raise ValueError("invalid token signature")

    try:
        payload = json.loads(_b64url_decode(payload_part).decode("utf-8"))
    except Exception as exc:
        raise ValueError("invalid token payload") from exc
    exp = int(payload.get("exp", 0))
    if exp <= int(datetime.now(timezone.utc).timestamp()):
        raise ValueError("token expired")

    return payload
