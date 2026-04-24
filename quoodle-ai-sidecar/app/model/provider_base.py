from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any


@dataclass
class ProviderResult:
    text: str
    provider: str
    model: str
    api_mode: str
    status: str
    degraded: bool
    response_id: str | None
    request_hash: str
    input_tokens: int | None
    output_tokens: int | None
    latency_ms: int
    error_code: str | None = None
    prompt_id: str | None = None
    prompt_version: str | None = None
    prompt_source: str | None = None
    prompt_hash: str | None = None


class ProviderBase(ABC):
    @abstractmethod
    async def generate(
        self,
        query: str,
        context: dict[str, Any],
        tool_outputs: dict[str, dict[str, Any]],
        correlation_id: str,
    ) -> ProviderResult:
        raise NotImplementedError
