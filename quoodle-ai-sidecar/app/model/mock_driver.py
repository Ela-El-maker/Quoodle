from __future__ import annotations

from typing import Any

from app.core.hashing import sha256_json
from app.model.provider_base import ProviderBase, ProviderResult


class MockDriver(ProviderBase):
    async def generate(
        self,
        query: str,
        context: dict[str, Any],
        tool_outputs: dict[str, dict[str, Any]],
        correlation_id: str,
    ) -> ProviderResult:
        device = tool_outputs.get("get_device_summary", {})
        telemetry = tool_outputs.get("get_latest_telemetry", {})
        failures = tool_outputs.get("get_command_failures", {})
        failure_count = int(failures.get("failure_count") or 0)
        lifecycle = str(device.get("lifecycle_state") or "unknown")
        risk = device.get("risk_score")
        cpu = (telemetry.get("metrics") or {}).get("cpu")
        ram = (telemetry.get("metrics") or {}).get("ram")

        if failure_count > 0:
            headline = (
                f"Device health appears degraded: {failure_count} recent failed or expired commands "
                f"with lifecycle state `{lifecycle}`."
            )
        else:
            headline = f"Device health appears stable with lifecycle state `{lifecycle}`."

        details = (
            f"Observed risk score is `{risk}` and recent telemetry shows cpu `{cpu}` and ram `{ram}`. "
            "This answer is generated in fallback mode due to model unavailability."
        )

        text = f"{headline} {details} Query: {query.strip()}"
        return ProviderResult(
            text=text,
            provider="mock",
            model="local-fallback",
            api_mode="responses",
            status="ok",
            degraded=True,
            response_id=None,
            request_hash=sha256_json(
                {
                    "query": query,
                    "context": context,
                    "tool_outputs": tool_outputs,
                    "correlation_id": correlation_id,
                }
            ),
            input_tokens=None,
            output_tokens=None,
            latency_ms=0,
            error_code="provider_unavailable",
            prompt_id="device_health",
            prompt_version="v1",
            prompt_source="fallback",
            prompt_hash=sha256_json({"mode": "mock_fallback", "query": query}),
        )
