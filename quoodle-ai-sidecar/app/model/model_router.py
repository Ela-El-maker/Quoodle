from __future__ import annotations

from typing import Any

from app.core.config import settings
from app.model.mock_driver import MockDriver
from app.model.provider_base import ProviderResult
from app.model.qwen_responses_driver import QwenResponsesDriver


class ModelRouter:
    def __init__(self) -> None:
        self._mock = MockDriver()
        self._qwen = QwenResponsesDriver()

    async def generate(
        self,
        query: str,
        context: dict[str, Any],
        tool_outputs: dict[str, dict[str, Any]],
        correlation_id: str,
    ) -> ProviderResult:
        if not settings.ai_provider_qwen_enabled:
            return await self._mock.generate(query, context, tool_outputs, correlation_id)

        try:
            return await self._qwen.generate(query, context, tool_outputs, correlation_id)
        except Exception as exc:
            fallback = await self._mock.generate(query, context, tool_outputs, correlation_id)
            fallback.error_code = str(exc) or exc.__class__.__name__
            fallback.status = "degraded"
            return fallback
