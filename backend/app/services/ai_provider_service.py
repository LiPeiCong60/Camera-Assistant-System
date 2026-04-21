"""Real AI provider invocation helpers."""

from __future__ import annotations

import base64
import json
import mimetypes
import re
from pathlib import Path
from typing import Any, Sequence
from urllib.parse import unquote, urlparse

import httpx

from backend.app.models.ai_provider_config import AiProviderConfig
from backend.app.models.capture import Capture


class AiProviderInvocationError(RuntimeError):
    """Raised when a real provider request cannot be completed."""


class AiProviderService:
    """Dispatches real AI requests to configured providers."""

    def __init__(self, config: AiProviderConfig) -> None:
        self.config = config

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
        if not self.config.api_key:
            raise AiProviderInvocationError("api_key is missing")
        if not self.config.model_name:
            raise AiProviderInvocationError("model_name is missing")

        endpoint = self._normalize_chat_endpoint(self.config.api_base_url)
        extra_config = self.config.extra_config or {}
        timeout_seconds = float(extra_config.get("timeout_seconds", 60))
        max_tokens = int(extra_config.get("max_tokens", 800))
        temperature = float(extra_config.get("temperature", 0.2))

        content: list[dict[str, Any]] = [
            {
                "type": "text",
                "text": (
                    "Select the single best portrait photo from this batch. "
                    "Return only JSON. Keep `summary` in Simplified Chinese. "
                    "Use one of the provided `capture_id` values as `best_capture_id`."
                ),
            }
        ]
        for capture in captures:
            content.append(
                {
                    "type": "text",
                    "text": f"capture_id={capture.id}, score_hint={capture.score or 0}, type={capture.capture_type}",
                }
            )
            content.append(self._build_image_content(capture))

        messages = [
            {
                "role": "system",
                "content": (
                    "You are a portrait photo picker. "
                    "Respond with valid JSON only, no markdown fences, no extra text. "
                    "JSON schema: "
                    "{"
                    '"task_type": "batch_pick", '
                    '"best_capture_id": <integer>, '
                    '"summary": "<string>", '
                    '"score": <number>'
                    "}."
                ),
            },
            {"role": "user", "content": content},
        ]

        payload = {
            "model": self.config.model_name,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }
        headers = {
            "Authorization": f"Bearer {self.config.api_key}",
            "Content-Type": "application/json",
        }

        try:
            with httpx.Client(timeout=timeout_seconds) as client:
                response = client.post(endpoint, headers=headers, json=payload)
                response.raise_for_status()
                raw_response = response.json()
        except httpx.HTTPStatusError as exc:
            detail = exc.response.text[:500]
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
        if not self.config.api_key:
            raise AiProviderInvocationError("api_key is missing")
        if not self.config.model_name:
            raise AiProviderInvocationError("model_name is missing")

        endpoint = self._normalize_chat_endpoint(self.config.api_base_url)
        image_content = self._build_image_content(capture)
        extra_config = self.config.extra_config or {}
        timeout_seconds = float(extra_config.get("timeout_seconds", 60))
        max_tokens = int(extra_config.get("max_tokens", 800))
        temperature = float(extra_config.get("temperature", 0.2))

        messages = [
            {
                "role": "system",
                "content": (
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
                ),
            },
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    image_content,
                ],
            },
        ]

        payload = {
            "model": self.config.model_name,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }
        headers = {
            "Authorization": f"Bearer {self.config.api_key}",
            "Content-Type": "application/json",
        }

        try:
            with httpx.Client(timeout=timeout_seconds) as client:
                response = client.post(endpoint, headers=headers, json=payload)
                response.raise_for_status()
                raw_response = response.json()
        except httpx.HTTPStatusError as exc:
            detail = exc.response.text[:500]
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

    def _build_image_content(self, capture: Capture) -> dict[str, Any]:
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
            if parsed.scheme in {"http", "https"}:
                return {"type": "image_url", "image_url": {"url": file_url}}
            image_path = self._resolve_local_path(file_url, parsed)
        if not image_path.exists():
            raise AiProviderInvocationError(f"capture image not found: {image_path}")

        mime_type = mimetypes.guess_type(image_path.name)[0] or "image/jpeg"
        image_base64 = base64.b64encode(image_path.read_bytes()).decode("ascii")
        return {
            "type": "image_url",
            "image_url": {"url": f"data:{mime_type};base64,{image_base64}"},
        }

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
        cleaned = content_text.strip()
        if cleaned.startswith("```"):
            cleaned = re.sub(r"^```(?:json)?", "", cleaned, flags=re.IGNORECASE).strip()
            cleaned = re.sub(r"```$", "", cleaned).strip()

        try:
            parsed = json.loads(cleaned)
        except json.JSONDecodeError:
            first = cleaned.find("{")
            last = cleaned.rfind("}")
            if first == -1 or last == -1 or last <= first:
                raise AiProviderInvocationError("provider did not return parseable JSON") from None
            try:
                parsed = json.loads(cleaned[first : last + 1])
            except json.JSONDecodeError as exc:
                raise AiProviderInvocationError("provider returned malformed JSON") from exc

        if not isinstance(parsed, dict):
            raise AiProviderInvocationError("provider JSON root must be an object")

        task_type = str(parsed.get("task_type") or expected_task_type)
        target_box_norm = parsed.get("target_box_norm")
        if not isinstance(target_box_norm, list) or len(target_box_norm) != 4:
            raise AiProviderInvocationError("target_box_norm must be a list with 4 numbers")

        try:
            normalized_box = [round(float(item), 4) for item in target_box_norm]
            recommended_pan_delta = round(float(parsed.get("recommended_pan_delta", 0.0)), 2)
            recommended_tilt_delta = round(float(parsed.get("recommended_tilt_delta", 0.0)), 2)
            score = round(float(parsed.get("score", 0.0)), 2)
        except (TypeError, ValueError) as exc:
            raise AiProviderInvocationError("provider JSON contains invalid numeric fields") from exc

        summary = str(parsed.get("summary") or "").strip()
        if not summary:
            raise AiProviderInvocationError("provider JSON summary is empty")

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
