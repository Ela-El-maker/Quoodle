from __future__ import annotations

import time
from typing import Any

import httpx

from app.core.config import settings
from app.core.hashing import sha256_json
from app.model.provider_base import ProviderBase, ProviderResult
from app.prompts import PromptTemplateManager


class QwenResponsesDriver(ProviderBase):
    def __init__(self) -> None:
        self._prompts = PromptTemplateManager(
            templates_dir=settings.prompt_templates_dir,
            prompt_id=settings.prompt_profile,
            prompt_version=settings.prompt_version,
        )

    async def generate(
        self,
        query: str,
        context: dict[str, Any],
        tool_outputs: dict[str, dict[str, Any]],
        correlation_id: str,
    ) -> ProviderResult:
        if not settings.qwen_api_key.strip():
            raise RuntimeError("qwen_key_missing")

        prompt_bundle = self._prompts.build(query=query, context=context, tool_outputs=tool_outputs)
        api_mode = self._normalized_api_mode(settings.qwen_api_mode)
        output_token_budget = max(settings.qwen_max_output_tokens, 1024)
        if api_mode == "chat_completions":
            path = "/chat/completions"
            request_payload = {
                "model": settings.qwen_model,
                "messages": [
                    {"role": "system", "content": prompt_bundle.system_prompt},
                    {"role": "user", "content": prompt_bundle.user_prompt},
                ],
                "temperature": 0.4,
                "top_p": 0.95,
                "max_tokens": output_token_budget,
                "stream": False,
            }
        else:
            path = "/responses"
            request_payload = {
                "model": settings.qwen_model,
                "store": False,
                "max_output_tokens": output_token_budget,
                "input": [
                    {
                        "role": "system",
                        "content": [{"type": "input_text", "text": prompt_bundle.system_prompt}],
                    },
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "input_text",
                                "text": prompt_bundle.user_prompt,
                            }
                        ],
                    },
                ],
        }
        request_hash = sha256_json(request_payload)
        start = time.perf_counter()
        timeout = httpx.Timeout(
            timeout=settings.qwen_timeout_seconds,
            connect=min(settings.qwen_timeout_seconds, 10.0),
        )
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.post(
                f"{settings.qwen_base_url.rstrip('/')}{path}",
                headers={
                    "Authorization": f"Bearer {settings.qwen_api_key}",
                    "Content-Type": "application/json",
                    "X-Correlation-ID": correlation_id,
                },
                json=request_payload,
            )

        latency_ms = int((time.perf_counter() - start) * 1000)
        if response.status_code >= 400:
            raise RuntimeError(f"qwen_http_{response.status_code}")

        data = response.json()
        text = self._extract_text(data, api_mode)
        usage = data.get("usage", {}) if isinstance(data, dict) else {}
        input_tokens = self._safe_int(usage.get("input_tokens"))
        output_tokens = self._safe_int(usage.get("output_tokens"))
        if api_mode == "chat_completions":
            input_tokens = input_tokens if input_tokens is not None else self._safe_int(usage.get("prompt_tokens"))
            output_tokens = output_tokens if output_tokens is not None else self._safe_int(usage.get("completion_tokens"))

        return ProviderResult(
            text=text or "",
            provider="qwen",
            model=settings.qwen_model,
            api_mode=api_mode,
            status="ok",
            degraded=False,
            response_id=str(data.get("id")) if isinstance(data, dict) and data.get("id") else None,
            request_hash=request_hash,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            latency_ms=latency_ms,
            prompt_id=prompt_bundle.prompt_id,
            prompt_version=prompt_bundle.prompt_version,
            prompt_source=prompt_bundle.prompt_source,
            prompt_hash=prompt_bundle.prompt_hash,
        )

    def _extract_text(self, data: Any, api_mode: str) -> str:
        if api_mode == "chat_completions":
            return self._extract_chat_text(data)
        return self._extract_responses_text(data)

    def _extract_responses_text(self, data: Any) -> str:
        if isinstance(data, dict):
            output_text = data.get("output_text")
            if isinstance(output_text, str) and output_text.strip():
                return output_text.strip()

            output = data.get("output")
            if isinstance(output, list):
                chunks: list[str] = []
                for item in output:
                    if not isinstance(item, dict):
                        continue
                    content = item.get("content")
                    if not isinstance(content, list):
                        continue
                    for part in content:
                        if isinstance(part, dict):
                            text = part.get("text")
                            if isinstance(text, str) and text.strip():
                                chunks.append(text.strip())
                if chunks:
                    return "\n".join(chunks)
        return ""

    def _extract_chat_text(self, data: Any) -> str:
        if not isinstance(data, dict):
            return ""
        choices = data.get("choices")
        if not isinstance(choices, list) or not choices:
            return ""
        first = choices[0]
        if not isinstance(first, dict):
            return ""
        message = first.get("message")
        if not isinstance(message, dict):
            return ""
        content = message.get("content")
        if isinstance(content, str):
            return content.strip()
        if isinstance(content, list):
            chunks: list[str] = []
            for part in content:
                if isinstance(part, dict):
                    txt = part.get("text")
                    if isinstance(txt, str) and txt.strip():
                        chunks.append(txt.strip())
            if chunks:
                return "\n".join(chunks)
        return ""

    def _safe_int(self, value: Any) -> int | None:
        try:
            if value is None:
                return None
            return int(value)
        except Exception:
            return None

    def _normalized_api_mode(self, value: str) -> str:
        mode = (value or "").strip().lower()
        if mode in {"chat", "chat_completion", "chat_completions"}:
            return "chat_completions"
        return "responses"
