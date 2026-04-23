"""Real AI provider invocation helpers."""

from __future__ import annotations

import base64
import copy
import json
import logging
import mimetypes
import os
import re
from pathlib import Path
from typing import Any, Sequence
from urllib.parse import unquote, urlparse

import httpx

from backend.app.models.ai_provider_config import AiProviderConfig
from backend.app.models.capture import Capture

DEFAULT_TARGET_BOX_NORM: tuple[float, float, float, float] = (0.38, 0.18, 0.24, 0.66)


class AiProviderInvocationError(RuntimeError):
    """Raised when a real provider request cannot be completed."""


class AiProviderService:
    """Dispatches real AI requests to configured providers."""

    def __init__(self, config: AiProviderConfig) -> None:
        self.config = config
        self._logger = logging.getLogger(__name__)

    def analyze_photo(self, capture: Capture, provider_metadata: dict[str, Any]) -> dict[str, Any]:
        return self._invoke_structured_vision_task(
            capture=capture,
            provider_metadata=provider_metadata,
            prompt=(
                "Analyze the portrait composition in this image. "
                "Return only JSON. Keep `summary` in Simplified Chinese. "
                "If the subject is already centered, keep deltas close to 0."
            ),
            expected_task_type="analyze_photo",
        )

    def analyze_background(self, capture: Capture, provider_metadata: dict[str, Any]) -> dict[str, Any]:
        return self._invoke_structured_vision_task(
            capture=capture,
            provider_metadata=provider_metadata,
            prompt=(
                "Analyze the background and framing of this portrait image. "
                "Return only JSON for a better camera lock position. "
                "Keep `summary` in Simplified Chinese."
            ),
            expected_task_type="background_lock",
        )

    def batch_pick(self, captures: Sequence[Capture], provider_metadata: dict[str, Any]) -> dict[str, Any]:
        if not captures:
            raise AiProviderInvocationError("batch-pick requires at least one capture")
        if self.config.provider_format != "openai_compatible":
            raise AiProviderInvocationError(
                f"provider_format `{self.config.provider_format}` is not supported yet"
            )
        if not self.config.api_base_url:
            raise AiProviderInvocationError("api_base_url is missing")
        if self._provider_requires_api_key() and not self.config.api_key:
            raise AiProviderInvocationError("api_key is missing")
        if not self.config.model_name:
            raise AiProviderInvocationError("model_name is missing")

        endpoint = self._normalize_chat_endpoint(self.config.api_base_url)
        extra_config = self.config.extra_config or {}
        timeout_seconds = float(extra_config.get("timeout_seconds", 60))
        max_tokens = int(extra_config.get("max_tokens", 800))
        temperature = float(extra_config.get("temperature", 0.2))

        messages = self._build_batch_pick_messages(captures)

        payload = {
            "model": self.config.model_name,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": False,
        }
        if self._uses_longcat_vision_format():
            payload["sessionId"] = f"batch_pick_{captures[0].session_id}_{captures[0].id}"
            payload["topP"] = 0.1
            payload["topK"] = 1
            payload["textRepetitionPenalty"] = 1.0
            payload["audioRepetitionPenalty"] = 1.1
            payload["inferenceCount"] = 1
            payload["output_modalities"] = ["text"]
        headers = self._build_provider_headers()

        try:
            raw_response = self._post_provider_json(
                endpoint=endpoint,
                headers=headers,
                payload=payload,
                timeout_seconds=timeout_seconds,
            )
        except httpx.HTTPStatusError as exc:
            detail = exc.response.text[:500]
            self._log_provider_http_error(endpoint, payload, exc.response.status_code, exc.response.text)
            raise AiProviderInvocationError(
                f"provider returned HTTP {exc.response.status_code}: {detail}"
            ) from exc
        except httpx.HTTPError as exc:
            raise AiProviderInvocationError(f"provider request failed: {exc}") from exc
        except ValueError as exc:
            raise AiProviderInvocationError("provider response is not valid JSON") from exc

        content_text = self._extract_message_text(raw_response)
        result = self._parse_batch_pick_result(content_text, captures)
        result["provider_metadata"] = {
            **provider_metadata,
            "mode": "real_provider",
            "request_endpoint": endpoint,
            "response_id": raw_response.get("id"),
            "usage": raw_response.get("usage"),
        }
        return result

    def _invoke_structured_vision_task(
        self,
        *,
        capture: Capture,
        provider_metadata: dict[str, Any],
        prompt: str,
        expected_task_type: str,
    ) -> dict[str, Any]:
        if self.config.provider_format != "openai_compatible":
            raise AiProviderInvocationError(
                f"provider_format `{self.config.provider_format}` is not supported yet"
            )
        if not self.config.api_base_url:
            raise AiProviderInvocationError("api_base_url is missing")
        if self._provider_requires_api_key() and not self.config.api_key:
            raise AiProviderInvocationError("api_key is missing")
        if not self.config.model_name:
            raise AiProviderInvocationError("model_name is missing")

        endpoint = self._normalize_chat_endpoint(self.config.api_base_url)
        extra_config = self.config.extra_config or {}
        timeout_seconds = float(extra_config.get("timeout_seconds", 60))
        max_tokens = int(extra_config.get("max_tokens", 800))
        temperature = float(extra_config.get("temperature", 0.2))

        messages = self._build_structured_messages(capture=capture, prompt=prompt)

        payload = {
            "model": self.config.model_name,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": False,
        }
        if self._uses_longcat_vision_format():
            payload["sessionId"] = f"{expected_task_type}_{capture.session_id}_{capture.id}"
            payload["topP"] = 0.1
            payload["topK"] = 1
            payload["textRepetitionPenalty"] = 1.0
            payload["audioRepetitionPenalty"] = 1.1
            payload["inferenceCount"] = 1
            payload["output_modalities"] = ["text"]
        headers = self._build_provider_headers()

        try:
            raw_response = self._post_provider_json(
                endpoint=endpoint,
                headers=headers,
                payload=payload,
                timeout_seconds=timeout_seconds,
            )
        except httpx.HTTPStatusError as exc:
            detail = exc.response.text[:500]
            self._log_provider_http_error(endpoint, payload, exc.response.status_code, exc.response.text)
            raise AiProviderInvocationError(
                f"provider returned HTTP {exc.response.status_code}: {detail}"
            ) from exc
        except httpx.HTTPError as exc:
            raise AiProviderInvocationError(f"provider request failed: {exc}") from exc
        except ValueError as exc:
            raise AiProviderInvocationError("provider response is not valid JSON") from exc

        content_text = self._extract_message_text(raw_response)
        result = self._parse_structured_result(content_text, expected_task_type)
        result["provider_metadata"] = {
            **provider_metadata,
            "mode": "real_provider",
            "request_endpoint": endpoint,
            "response_id": raw_response.get("id"),
            "usage": raw_response.get("usage"),
        }
        return result

    def _normalize_chat_endpoint(self, api_base_url: str) -> str:
        cleaned = api_base_url.strip().strip("\"'").rstrip("/")
        if cleaned.endswith("/v1/chat/completions"):
            return cleaned
        if cleaned.endswith("/chat/completions"):
            return cleaned
        if cleaned.endswith("/v1"):
            return f"{cleaned}/chat/completions"
        return f"{cleaned}/v1/chat/completions"

    def _provider_requires_api_key(self) -> bool:
        return not self._uses_ollama_provider()

    def _build_provider_headers(self) -> dict[str, str]:
        api_key = (self.config.api_key or "").strip()
        if not api_key and self._uses_ollama_provider():
            api_key = "ollama"
        headers = {"Content-Type": "application/json"}
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"
        return headers

    def _uses_ollama_provider(self) -> bool:
        return (self.config.vendor_name or "").strip().lower() == "ollama"

    def _build_structured_messages(self, *, capture: Capture, prompt: str) -> list[dict[str, Any]]:
        system_prompt = (
            "You are a camera composition assistant. "
            "Respond with valid JSON only, no markdown fences, no extra text. "
            "JSON schema: "
            "{"
            '"task_type": "<string>", '
            '"recommended_pan_delta": <number>, '
            '"recommended_tilt_delta": <number>, '
            '"target_box_norm": [x, y, w, h], '
            '"summary": "<string>", '
            '"score": <number>'
            "}."
        )
        if self._uses_longcat_vision_format():
            return [
                {
                    "role": "system",
                    "content": [{"type": "text", "text": system_prompt}],
                },
                {
                    "role": "user",
                    "content": [
                        self._build_image_content(capture, format_style="longcat"),
                        {"type": "text", "text": prompt},
                    ],
                },
            ]

        return [
            {"role": "system", "content": system_prompt},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    self._build_image_content(capture, format_style="openai"),
                ],
            },
        ]

    def _build_batch_pick_messages(self, captures: Sequence[Capture]) -> list[dict[str, Any]]:
        system_prompt = (
            "You are a portrait photo picker. "
            "Respond with valid JSON only, no markdown fences, no extra text. "
            "JSON schema: "
            "{"
            '"task_type": "batch_pick", '
            '"best_capture_id": <integer>, '
            '"summary": "<string>", '
            '"score": <number>'
            "}."
        )
        user_content: list[dict[str, Any]] = [
            {
                "type": "text",
                "text": (
                    "Select the single best portrait photo from this batch. "
                    "Return only JSON. Keep `summary` in Simplified Chinese. "
                    "Use one of the provided `capture_id` values as `best_capture_id`."
                ),
            }
        ]
        image_format = "longcat" if self._uses_longcat_vision_format() else "openai"
        for capture in captures:
            user_content.append(
                {
                    "type": "text",
                    "text": f"capture_id={capture.id}, score_hint={capture.score or 0}, type={capture.capture_type}",
                }
            )
            user_content.append(self._build_image_content(capture, format_style=image_format))

        if self._uses_longcat_vision_format():
            return [
                {
                    "role": "system",
                    "content": [{"type": "text", "text": system_prompt}],
                },
                {"role": "user", "content": user_content},
            ]

        return [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content},
        ]

    def _build_image_content(self, capture: Capture, *, format_style: str = "openai") -> dict[str, Any]:
        file_url = capture.file_url
        storage_path = None
        if isinstance(capture_metadata := getattr(capture, "capture_metadata", None), dict):
            raw_storage_path = capture_metadata.get("storage_path")
            if isinstance(raw_storage_path, str) and raw_storage_path.strip():
                storage_path = Path(raw_storage_path.strip())

        if storage_path is not None:
            image_path = storage_path
        elif not file_url:
            raise AiProviderInvocationError("capture file_url is empty")
        else:
            parsed = urlparse(file_url)
            if format_style == "openai" and parsed.scheme in {"http", "https"}:
                return {"type": "image_url", "image_url": {"url": file_url}}
            image_path = self._resolve_local_path(file_url, parsed)
        if not image_path.exists():
            raise AiProviderInvocationError(f"capture image not found: {image_path}")

        if format_style == "longcat":
            return self._build_longcat_image_content(image_path)
        return self._build_openai_image_content(image_path)

    def _build_openai_image_content(self, image_path: Path) -> dict[str, Any]:
        image_bytes, mime_type = self._prepare_image_bytes_for_upload(image_path)
        image_base64 = base64.b64encode(image_bytes).decode("ascii")
        return {
            "type": "image_url",
            "image_url": {
                "url": f"data:{mime_type};base64,{image_base64}",
                "detail": "low",
            },
        }

    def _build_longcat_image_content(self, image_path: Path) -> dict[str, Any]:
        if not self._supports_longcat_vision_model():
            raise AiProviderInvocationError(
                "LongCat current model does not support image input. "
                "Please switch the admin AI model to a LongCat Omni model such as `LongCat-Flash-Omni-2603`."
            )

        image_bytes, mime_type = self._prepare_image_bytes_for_upload(image_path)
        image_base64 = base64.b64encode(image_bytes).decode("ascii")
        return {
            "type": "input_image",
            "input_image": {
                "type": "base64",
                "data": image_base64,
                "_mime_type": mime_type,
            },
        }

    def _uses_longcat_vision_format(self) -> bool:
        return (self.config.vendor_name or "").strip().lower() == "longcat"

    def _supports_longcat_vision_model(self) -> bool:
        return "omni" in (self.config.model_name or "").strip().lower()

    def _post_provider_json(
        self,
        *,
        endpoint: str,
        headers: dict[str, str],
        payload: dict[str, Any],
        timeout_seconds: float,
    ) -> dict[str, Any]:
        variants = self._build_provider_payload_variants(payload)
        last_http_error: httpx.HTTPStatusError | None = None
        last_value_error: ValueError | None = None

        with httpx.Client(timeout=timeout_seconds) as client:
            for index, (variant_name, variant_payload) in enumerate(variants):
                request_payload = self._strip_internal_fields(copy.deepcopy(variant_payload))
                self._log_provider_request(endpoint, request_payload, variant_name=variant_name)
                try:
                    response = client.post(endpoint, headers=headers, json=request_payload)
                    response.raise_for_status()
                    return response.json()
                except httpx.HTTPStatusError as exc:
                    last_http_error = exc
                    self._log_provider_http_error(
                        endpoint,
                        request_payload,
                        exc.response.status_code,
                        exc.response.text,
                        variant_name=variant_name,
                    )
                    if not self._should_retry_provider_request(
                        exc,
                        current_index=index,
                        total_variants=len(variants),
                    ):
                        raise
                except ValueError as exc:
                    last_value_error = exc
                    break

        if last_http_error is not None:
            raise last_http_error
        if last_value_error is not None:
            raise last_value_error
        raise AiProviderInvocationError("provider request failed before receiving a response")

    def _build_provider_payload_variants(self, payload: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
        if not self._uses_longcat_vision_format():
            return [("default", payload)]

        variants: list[tuple[str, dict[str, Any]]] = []
        variants.append(("longcat-base64-sessionId", payload))

        base64_array_payload = copy.deepcopy(payload)
        self._transform_longcat_image_data(base64_array_payload, mode="base64_array", session_key="sessionId")
        variants.append(("longcat-base64-array-sessionId", base64_array_payload))

        data_url_array_payload = copy.deepcopy(payload)
        self._transform_longcat_image_data(data_url_array_payload, mode="data_url_array", session_key="sessionId")
        variants.append(("longcat-data-url-array-sessionId", data_url_array_payload))

        openai_image_url_payload = copy.deepcopy(payload)
        self._transform_longcat_to_openai_image_url(openai_image_url_payload, session_key="sessionId")
        variants.append(("longcat-openai-image-url-sessionId", openai_image_url_payload))

        snake_case_payload = copy.deepcopy(payload)
        self._transform_longcat_image_data(snake_case_payload, mode="base64_raw", session_key="session_id")
        variants.append(("longcat-base64-session_id", snake_case_payload))

        snake_case_data_url_payload = copy.deepcopy(payload)
        self._transform_longcat_image_data(snake_case_data_url_payload, mode="data_url_array", session_key="session_id")
        variants.append(("longcat-data-url-array-session_id", snake_case_data_url_payload))

        return variants

    def _transform_longcat_image_data(
        self,
        payload: dict[str, Any],
        *,
        mode: str,
        session_key: str,
    ) -> None:
        session_value = payload.pop("sessionId", None)
        payload.pop("session_id", None)
        if session_value is not None:
            payload[session_key] = session_value

        for message in payload.get("messages", []):
            if not isinstance(message, dict):
                continue
            content = message.get("content")
            if not isinstance(content, list):
                continue
            for item in content:
                if not isinstance(item, dict) or item.get("type") != "input_image":
                    continue
                image_obj = item.get("input_image")
                if not isinstance(image_obj, dict):
                    continue
                raw_data = image_obj.get("data")
                mime_type = str(image_obj.get("_mime_type") or "image/jpeg")
                if not isinstance(raw_data, str):
                    continue
                if mode == "base64_array":
                    image_obj["data"] = [raw_data]
                    image_obj["type"] = "base64"
                elif mode == "data_url_array":
                    image_obj["data"] = [f"data:{mime_type};base64,{raw_data}"]
                    image_obj["type"] = "url"
                else:
                    image_obj["data"] = raw_data
                    image_obj["type"] = "base64"

    def _transform_longcat_to_openai_image_url(
        self,
        payload: dict[str, Any],
        *,
        session_key: str,
    ) -> None:
        session_value = payload.pop("sessionId", None)
        payload.pop("session_id", None)
        if session_value is not None:
            payload[session_key] = session_value

        for message in payload.get("messages", []):
            if not isinstance(message, dict):
                continue
            content = message.get("content")
            if not isinstance(content, list):
                continue
            for index, item in enumerate(content):
                if not isinstance(item, dict) or item.get("type") != "input_image":
                    continue
                image_obj = item.get("input_image")
                if not isinstance(image_obj, dict):
                    continue
                raw_data = image_obj.get("data")
                mime_type = str(image_obj.get("_mime_type") or "image/jpeg")
                if not isinstance(raw_data, str):
                    continue
                content[index] = {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:{mime_type};base64,{raw_data}",
                    },
                }

    def _should_retry_provider_request(
        self,
        exc: httpx.HTTPStatusError,
        *,
        current_index: int,
        total_variants: int,
    ) -> bool:
        if exc.response.status_code != 400:
            return False
        if not self._uses_longcat_vision_format():
            return False
        return current_index < total_variants - 1

    def _strip_internal_fields(self, value: Any) -> Any:
        if isinstance(value, dict):
            sanitized: dict[str, Any] = {}
            for key, item in value.items():
                if key.startswith("_"):
                    continue
                sanitized[key] = self._strip_internal_fields(item)
            return sanitized
        if isinstance(value, list):
            return [self._strip_internal_fields(item) for item in value]
        return value

    def _log_provider_request(self, endpoint: str, payload: dict[str, Any], *, variant_name: str | None = None) -> None:
        payload_for_log = (
            json.dumps(self._sanitize_payload_for_log(payload), ensure_ascii=False)
            if self._verbose_provider_logs_enabled()
            else json.dumps(self._summarize_payload_for_log(payload), ensure_ascii=False)
        )
        try:
            self._logger.warning(
                "AI provider request endpoint=%s vendor=%s model=%s variant=%s payload=%s",
                endpoint,
                self.config.vendor_name,
                self.config.model_name,
                variant_name or "default",
                payload_for_log,
            )
        except Exception:
            self._logger.warning(
                "AI provider request endpoint=%s vendor=%s model=%s variant=%s payload=<unserializable>",
                endpoint,
                self.config.vendor_name,
                self.config.model_name,
                variant_name or "default",
            )

    def _log_provider_http_error(
        self,
        endpoint: str,
        payload: dict[str, Any],
        status_code: int,
        response_text: str,
        *,
        variant_name: str | None = None,
    ) -> None:
        payload_for_log = (
            json.dumps(self._sanitize_payload_for_log(payload), ensure_ascii=False)
            if self._verbose_provider_logs_enabled()
            else json.dumps(self._summarize_payload_for_log(payload), ensure_ascii=False)
        )
        try:
            self._logger.error(
                "AI provider HTTP error endpoint=%s status=%s vendor=%s model=%s variant=%s payload=%s response=%s",
                endpoint,
                status_code,
                self.config.vendor_name,
                self.config.model_name,
                variant_name or "default",
                payload_for_log,
                response_text[:800],
            )
        except Exception:
            self._logger.error(
                "AI provider HTTP error endpoint=%s status=%s vendor=%s model=%s variant=%s response=%s",
                endpoint,
                status_code,
                self.config.vendor_name,
                self.config.model_name,
                variant_name or "default",
                response_text[:800],
            )

    def _verbose_provider_logs_enabled(self) -> bool:
        return os.getenv("BACKEND_VERBOSE_AI_PROVIDER_LOGS", "").strip().lower() in {
            "1",
            "true",
            "yes",
            "on",
        }

    def _summarize_payload_for_log(self, payload: dict[str, Any]) -> dict[str, Any]:
        messages = payload.get("messages")
        message_summaries: list[dict[str, Any]] = []

        if isinstance(messages, list):
            for message in messages:
                if not isinstance(message, dict):
                    continue
                content = message.get("content")
                content_types: list[str] = []
                if isinstance(content, list):
                    for item in content:
                        if isinstance(item, dict):
                            item_type = item.get("type")
                            if isinstance(item_type, str):
                                content_types.append(item_type)
                elif isinstance(content, str):
                    content_types.append("text")

                message_summaries.append(
                    {
                        "role": message.get("role"),
                        "content_types": content_types,
                    }
                )

        summary = {
            "model": payload.get("model"),
            "message_count": len(messages) if isinstance(messages, list) else 0,
            "messages": message_summaries,
            "max_tokens": payload.get("max_tokens"),
            "temperature": payload.get("temperature"),
            "stream": payload.get("stream"),
            "sessionId": payload.get("sessionId"),
            "session_id": payload.get("session_id"),
            "output_modalities": payload.get("output_modalities"),
        }
        return summary

    def _sanitize_payload_for_log(self, value: Any) -> Any:
        if isinstance(value, dict):
            sanitized: dict[str, Any] = {}
            for key, item in value.items():
                if key in {"Authorization", "api_key"}:
                    sanitized[key] = "***"
                    continue
                if key == "input_image" and isinstance(item, dict):
                    sanitized[key] = self._sanitize_input_image(item)
                    continue
                if key == "image_url" and isinstance(item, dict):
                    sanitized[key] = self._sanitize_image_url(item)
                    continue
                sanitized[key] = self._sanitize_payload_for_log(item)
            return sanitized
        if isinstance(value, list):
            return [self._sanitize_payload_for_log(item) for item in value]
        return value

    def _sanitize_input_image(self, item: dict[str, Any]) -> dict[str, Any]:
        sanitized = dict(item)
        data = sanitized.get("data")
        if isinstance(data, str):
            sanitized["data"] = f"<base64 len={len(data)}>"
        return sanitized

    def _sanitize_image_url(self, item: dict[str, Any]) -> dict[str, Any]:
        sanitized = dict(item)
        url = sanitized.get("url")
        if isinstance(url, str) and url.startswith("data:"):
            sanitized["url"] = f"<data-url len={len(url)}>"
        return sanitized

    def _prepare_image_bytes_for_upload(self, image_path: Path) -> tuple[bytes, str]:
        ext = image_path.suffix.lower()
        mime_type = {
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".png": "image/png",
            ".webp": "image/webp",
            ".bmp": "image/bmp",
        }.get(ext, mimetypes.guess_type(image_path.name)[0] or "image/jpeg")
        optimized = self._read_image_bytes_for_upload(
            image_path,
            prefer_jpeg=(mime_type != "image/png"),
        )
        if optimized is None:
            return image_path.read_bytes(), mime_type
        return optimized

    def _read_image_bytes_for_upload(
        self,
        image_path: Path,
        *,
        prefer_jpeg: bool,
    ) -> tuple[bytes, str] | None:
        try:
            import cv2
        except Exception:
            return None

        image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
        if image is None:
            return None

        height, width = image.shape[:2]
        max_side = 720
        if max(height, width) > max_side:
            scale = float(max_side) / float(max(height, width))
            new_width = max(2, int(width * scale))
            new_height = max(2, int(height * scale))
            image = cv2.resize(image, (new_width, new_height), interpolation=cv2.INTER_AREA)

        if prefer_jpeg:
            ok, encoded = cv2.imencode(".jpg", image, [int(cv2.IMWRITE_JPEG_QUALITY), 70])
            mime_type = "image/jpeg"
        else:
            ok, encoded = cv2.imencode(".png", image, [int(cv2.IMWRITE_PNG_COMPRESSION), 3])
            mime_type = "image/png"

        if not ok:
            return None
        return encoded.tobytes(), mime_type

    def _resolve_local_path(self, file_url: str, parsed) -> Path:
        windows_path_pattern = re.compile(r"^[A-Za-z]:[\\/]")
        if windows_path_pattern.match(file_url):
            return Path(file_url)

        if parsed.scheme == "file":
            file_path = unquote(parsed.path or "")
            if re.match(r"^/[A-Za-z]:", file_path):
                file_path = file_path[1:]
            return Path(file_path)

        return Path(file_url)

    def _extract_message_text(self, raw_response: dict[str, Any]) -> str:
        try:
            message_content = raw_response["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise AiProviderInvocationError("provider response missing choices[0].message.content") from exc

        if isinstance(message_content, str):
            return message_content.strip()

        if isinstance(message_content, list):
            text_parts: list[str] = []
            for item in message_content:
                if isinstance(item, dict) and item.get("type") == "text":
                    text_parts.append(str(item.get("text", "")))
            combined = "\n".join(part for part in text_parts if part).strip()
            if combined:
                return combined

        raise AiProviderInvocationError("provider response content format is not supported")

    def _parse_structured_result(self, content_text: str, expected_task_type: str) -> dict[str, Any]:
        parsed = self._extract_json_object(content_text)
        if not isinstance(parsed, dict):
            return self._build_fallback_structured_result(content_text, expected_task_type)

        task_type = str(parsed.get("task_type") or expected_task_type).strip() or expected_task_type
        normalized_box = [
            round(item, 4)
            for item in self._safe_box_norm(parsed.get("target_box_norm"))
        ]
        recommended_pan_delta = round(
            self._coerce_float(parsed.get("recommended_pan_delta", 0.0), minimum=-20.0, maximum=20.0),
            2,
        )
        recommended_tilt_delta = round(
            self._coerce_float(parsed.get("recommended_tilt_delta", 0.0), minimum=-15.0, maximum=15.0),
            2,
        )
        score = round(
            self._coerce_float(parsed.get("score", 0.0), minimum=0.0, maximum=100.0),
            2,
        )
        summary = str(parsed.get("summary") or "").strip() or self._build_fallback_summary(
            content_text,
            expected_task_type,
        )

        return {
            "task_type": task_type,
            "recommended_pan_delta": recommended_pan_delta,
            "recommended_tilt_delta": recommended_tilt_delta,
            "target_box_norm": normalized_box,
            "summary": summary,
            "score": score,
        }

    def _parse_batch_pick_result(self, content_text: str, captures: Sequence[Capture]) -> dict[str, Any]:
        parsed = self._parse_json_object(content_text)
        if not isinstance(parsed, dict):
            raise AiProviderInvocationError("provider JSON root must be an object")

        valid_capture_ids = {capture.id for capture in captures}
        best_capture_id = parsed.get("best_capture_id")
        if not isinstance(best_capture_id, int):
            raise AiProviderInvocationError("best_capture_id must be an integer")
        if best_capture_id not in valid_capture_ids:
            raise AiProviderInvocationError("best_capture_id is not in requested capture_ids")

        summary = str(parsed.get("summary") or "").strip()
        if not summary:
            raise AiProviderInvocationError("provider JSON summary is empty")
        try:
            score = round(float(parsed.get("score", 0.0)), 2)
        except (TypeError, ValueError) as exc:
            raise AiProviderInvocationError("provider JSON contains invalid numeric fields") from exc

        return {
            "task_type": "batch_pick",
            "best_capture_id": best_capture_id,
            "summary": summary,
            "score": score,
        }

    def _extract_json_object(self, content_text: str) -> dict[str, Any] | None:
        cleaned = content_text.strip()
        if cleaned.startswith("```"):
            cleaned = re.sub(r"^```(?:json)?", "", cleaned, flags=re.IGNORECASE).strip()
            cleaned = re.sub(r"```$", "", cleaned).strip()

        try:
            parsed = json.loads(cleaned)
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            pass

        match = re.search(r"\{[\s\S]*\}", cleaned)
        if not match:
            return None
        try:
            parsed = json.loads(match.group(0))
        except json.JSONDecodeError:
            return None
        return parsed if isinstance(parsed, dict) else None

    def _build_fallback_structured_result(self, content_text: str, expected_task_type: str) -> dict[str, Any]:
        return {
            "task_type": expected_task_type,
            "recommended_pan_delta": 0.0,
            "recommended_tilt_delta": 0.0,
            "target_box_norm": [round(item, 4) for item in DEFAULT_TARGET_BOX_NORM],
            "summary": self._build_fallback_summary(content_text, expected_task_type),
            "score": 0.0,
        }

    def _build_fallback_summary(self, content_text: str, expected_task_type: str) -> str:
        cleaned = re.sub(r"\s+", " ", content_text).strip()
        if cleaned:
            return cleaned[:160]
        if expected_task_type == "background_lock":
            return "模型已返回结果，但未严格按结构化格式输出，已按默认背景建议处理。"
        return "模型已返回结果，但未严格按结构化格式输出，已按默认构图建议处理。"

    def _coerce_float(
        self,
        value: Any,
        *,
        minimum: float | None = None,
        maximum: float | None = None,
    ) -> float:
        try:
            result = float(value)
        except (TypeError, ValueError):
            result = 0.0
        if minimum is not None:
            result = max(minimum, result)
        if maximum is not None:
            result = min(maximum, result)
        return result

    def _safe_box_norm(self, raw: Any) -> tuple[float, float, float, float]:
        if isinstance(raw, (list, tuple)) and len(raw) == 4:
            try:
                x, y, w, h = [float(item) for item in raw]
                x = max(0.0, min(1.0, x))
                y = max(0.0, min(1.0, y))
                w = max(0.08, min(1.0, w))
                h = max(0.12, min(1.0, h))
                if x + w > 1.0:
                    x = max(0.0, 1.0 - w)
                if y + h > 1.0:
                    y = max(0.0, 1.0 - h)
                return (x, y, w, h)
            except (TypeError, ValueError):
                pass
        return DEFAULT_TARGET_BOX_NORM

    def _parse_json_object(self, content_text: str) -> Any:
        cleaned = content_text.strip()
        if cleaned.startswith("```"):
            cleaned = re.sub(r"^```(?:json)?", "", cleaned, flags=re.IGNORECASE).strip()
            cleaned = re.sub(r"```$", "", cleaned).strip()

        try:
            return json.loads(cleaned)
        except json.JSONDecodeError:
            first = cleaned.find("{")
            last = cleaned.rfind("}")
            if first == -1 or last == -1 or last <= first:
                raise AiProviderInvocationError("provider did not return parseable JSON") from None
            try:
                return json.loads(cleaned[first : last + 1])
            except json.JSONDecodeError as exc:
                raise AiProviderInvocationError("provider returned malformed JSON") from exc
