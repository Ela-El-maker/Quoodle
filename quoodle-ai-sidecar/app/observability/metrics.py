from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from threading import Lock


@dataclass
class SidecarMetrics:
    _lock: Lock = field(default_factory=Lock)
    requests_total: int = 0
    request_status: dict[str, int] = field(default_factory=lambda: defaultdict(int))
    request_latency_ms_total: int = 0
    request_latency_samples: int = 0
    tool_calls_total: dict[str, int] = field(default_factory=lambda: defaultdict(int))
    tool_failures_total: dict[str, int] = field(default_factory=lambda: defaultdict(int))
    tool_latency_ms_total: dict[str, int] = field(default_factory=lambda: defaultdict(int))
    guardrail_blocks_total: int = 0
    model_calls_total: dict[str, int] = field(default_factory=lambda: defaultdict(int))
    model_latency_ms_total: int = 0
    model_input_tokens_total: int = 0
    model_output_tokens_total: int = 0
    artifacts_created_total: dict[str, int] = field(default_factory=lambda: defaultdict(int))

    def record_request(self, status: str, latency_ms: int | None = None) -> None:
        with self._lock:
            self.requests_total += 1
            self.request_status[status] += 1
            if isinstance(latency_ms, int) and latency_ms >= 0:
                self.request_latency_ms_total += latency_ms
                self.request_latency_samples += 1

    def record_tool(self, tool_name: str, status: str, duration_ms: int | None = None) -> None:
        with self._lock:
            self.tool_calls_total[tool_name] += 1
            if status != "ok":
                self.tool_failures_total[tool_name] += 1
            if isinstance(duration_ms, int) and duration_ms >= 0:
                self.tool_latency_ms_total[tool_name] += duration_ms

    def record_guardrail_block(self) -> None:
        with self._lock:
            self.guardrail_blocks_total += 1

    def record_model(
        self,
        status: str,
        latency_ms: int | None = None,
        input_tokens: int | None = None,
        output_tokens: int | None = None,
    ) -> None:
        with self._lock:
            self.model_calls_total[status] += 1
            if isinstance(latency_ms, int) and latency_ms >= 0:
                self.model_latency_ms_total += latency_ms
            if isinstance(input_tokens, int) and input_tokens >= 0:
                self.model_input_tokens_total += input_tokens
            if isinstance(output_tokens, int) and output_tokens >= 0:
                self.model_output_tokens_total += output_tokens

    def record_artifact(self, artifact_type: str) -> None:
        with self._lock:
            self.artifacts_created_total[artifact_type] += 1

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            request_avg = (
                round(self.request_latency_ms_total / self.request_latency_samples, 2)
                if self.request_latency_samples > 0
                else None
            )
            return {
                "requests_total": self.requests_total,
                "request_status": dict(self.request_status),
                "request_latency_ms_total": self.request_latency_ms_total,
                "request_latency_ms_avg": request_avg,
                "tool_calls_total": dict(self.tool_calls_total),
                "tool_failures_total": dict(self.tool_failures_total),
                "tool_latency_ms_total": dict(self.tool_latency_ms_total),
                "guardrail_blocks_total": self.guardrail_blocks_total,
                "model_calls_total": dict(self.model_calls_total),
                "model_latency_ms_total": self.model_latency_ms_total,
                "model_input_tokens_total": self.model_input_tokens_total,
                "model_output_tokens_total": self.model_output_tokens_total,
                "artifacts_created_total": dict(self.artifacts_created_total),
            }


metrics = SidecarMetrics()
