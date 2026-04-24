from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Callable

from app.core.hashing import sha256_json
from app.schemas import ChatAskRequest


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _freshness_seconds(source_ts: str | None) -> int | None:
    if not source_ts:
        return None
    try:
        ts = source_ts
        if ts.endswith("Z"):
            ts = ts[:-1] + "+00:00"
        value = datetime.fromisoformat(ts)
        age = int((datetime.now(timezone.utc) - value.astimezone(timezone.utc)).total_seconds())
        return max(age, 0)
    except Exception:
        return None


@dataclass
class ToolRunResult:
    tool_calls: list[dict[str, Any]]
    tool_outputs: dict[str, dict[str, Any]]
    evidence_refs: list[dict[str, Any]]
    guardrail_events: list[dict[str, Any]]
    freshness_seconds: int | None


class ToolRouter:
    def __init__(self) -> None:
        self._tool_order = [
            "get_device_summary",
            "get_latest_telemetry",
            "get_command_failures",
            "search_audit_events",
            "get_system_health",
        ]

    async def run(self, payload: ChatAskRequest) -> ToolRunResult:
        tool_calls: list[dict[str, Any]] = []
        tool_outputs: dict[str, dict[str, Any]] = {}
        evidence_refs: list[dict[str, Any]] = []
        guardrail_events: list[dict[str, Any]] = []
        freshness_values: list[int] = []

        selected_device = payload.selected_refs.device_id
        allowed_devices = set(payload.scope_context.allowed_device_ids)
        scope_hash = sha256_json(sorted(allowed_devices))

        tools: dict[str, Callable[[], dict[str, Any]]] = {
            "get_device_summary": lambda: self._get_device_summary(payload, selected_device, allowed_devices),
            "get_latest_telemetry": lambda: self._get_latest_telemetry(payload, selected_device, allowed_devices),
            "get_command_failures": lambda: self._get_command_failures(payload, selected_device, allowed_devices),
            "search_audit_events": lambda: self._search_audit_events(payload, selected_device, allowed_devices),
            "get_system_health": lambda: self._get_system_health(payload),
        }

        for tool_name in self._tool_order:
            start = time.perf_counter()
            args = {"device_id": selected_device} if tool_name != "get_system_health" else {}
            input_hash = sha256_json(args)
            status = "ok"
            rows_returned = 0
            error_code = None
            result: dict[str, Any] = {}
            try:
                result = tools[tool_name]()
                rows_returned = self._estimate_rows(tool_name, result)
                if tool_name != "get_system_health" and selected_device not in allowed_devices:
                    status = "blocked"
                    error_code = "scope_violation"
                    result = self._blocked_result(tool_name)
                    guardrail_events.append(
                        {
                            "event_type": "guardrail.pre_tool",
                            "severity": "critical",
                            "detail": {"tool_name": tool_name, "reason": "scope_violation"},
                        }
                    )
            except Exception:
                status = "error"
                error_code = "tool_error"
                result = self._error_result(tool_name)

            duration_ms = int((time.perf_counter() - start) * 1000)
            output_hash = sha256_json(result)
            tool_calls.append(
                {
                    "tool_name": tool_name,
                    "status": status,
                    "duration_ms": max(duration_ms, 0),
                    "rows_returned": rows_returned,
                    "input_hash": input_hash,
                    "output_hash": output_hash,
                    "scope_hash": scope_hash,
                    "error_code": error_code,
                }
            )
            tool_outputs[tool_name] = result

            source_id = str(result.get("device_id") or result.get("event_type") or tool_name)
            source_ts = (
                result.get("timestamp")
                or result.get("last_seen")
                or result.get("fetched_at")
                or _now_iso()
            )
            freshness = result.get("freshness_seconds")
            if isinstance(freshness, int):
                freshness_values.append(freshness)
            else:
                derived = _freshness_seconds(source_ts if isinstance(source_ts, str) else None)
                if derived is not None:
                    freshness_values.append(derived)

            evidence_refs.append(
                {
                    "source_type": tool_name,
                    "source_id": source_id,
                    "source_timestamp": source_ts,
                    "excerpt_summary": self._excerpt(tool_name, result),
                    "excerpt_hash": output_hash,
                    "freshness_seconds": freshness if isinstance(freshness, int) else _freshness_seconds(source_ts if isinstance(source_ts, str) else None),
                    "confidence_weight": round(1.0 / float(len(self._tool_order)), 4),
                    "uri": self._evidence_uri(tool_name, selected_device),
                }
            )

        freshness_total = max(freshness_values) if freshness_values else None
        return ToolRunResult(
            tool_calls=tool_calls,
            tool_outputs=tool_outputs,
            evidence_refs=evidence_refs,
            guardrail_events=guardrail_events,
            freshness_seconds=freshness_total,
        )

    def _get_device_summary(
        self,
        payload: ChatAskRequest,
        selected_device: str,
        allowed_devices: set[str],
    ) -> dict[str, Any]:
        if selected_device not in allowed_devices:
            return self._blocked_result("get_device_summary")
        data = payload.context.device_summary or {}
        fetched_at = _now_iso()
        return {
            "device_id": data.get("device_id", selected_device),
            "device_name": data.get("device_name"),
            "lifecycle_state": data.get("lifecycle_state"),
            "last_seen": data.get("last_seen"),
            "risk_score": data.get("risk_score"),
            "compliance_status": data.get("resolved_compliance_status") or data.get("compliance_status"),
            "policy_in_sync": data.get("resolved_policy_in_sync") if data.get("resolved_policy_in_sync") is not None else data.get("policy_in_sync"),
            "owner_ref": data.get("owner_email"),
            "fetched_at": fetched_at,
            "freshness_seconds": _freshness_seconds(data.get("last_seen")),
            "authoritative_source": "laravel.device_projection",
            "redactions": ["owner_email_masked"],
        }

    def _get_latest_telemetry(
        self,
        payload: ChatAskRequest,
        selected_device: str,
        allowed_devices: set[str],
    ) -> dict[str, Any]:
        if selected_device not in allowed_devices:
            return self._blocked_result("get_latest_telemetry")
        data = payload.context.latest_telemetry or {}
        metrics = data.get("metrics") if isinstance(data.get("metrics"), dict) else {}
        return {
            "device_id": selected_device,
            "timestamp": data.get("timestamp"),
            "metrics": {
                "cpu": metrics.get("cpu"),
                "ram": metrics.get("ram"),
                "disk_usage": metrics.get("disk_usage"),
                "network_tx": metrics.get("network_tx"),
                "network_rx": metrics.get("network_rx"),
                "risk_score": metrics.get("risk_score"),
                "policy_hash": data.get("policy_hash") or metrics.get("policy_hash"),
            },
            "fetched_at": _now_iso(),
            "freshness_seconds": _freshness_seconds(data.get("timestamp")),
            "authoritative_source": "laravel.telemetry_latest",
            "redactions": [],
        }

    def _get_command_failures(
        self,
        payload: ChatAskRequest,
        selected_device: str,
        allowed_devices: set[str],
    ) -> dict[str, Any]:
        if selected_device not in allowed_devices:
            return self._blocked_result("get_command_failures")
        failures = payload.context.command_failures or []
        normalized = []
        for item in failures[:20]:
            normalized.append(
                {
                    "command_id": item.get("command_id"),
                    "method": item.get("method"),
                    "state": item.get("state"),
                    "error_code": item.get("error_code"),
                    "error_message": item.get("error_message"),
                    "timestamp": item.get("completed_at") or item.get("queued_at"),
                }
            )
        return {
            "device_id": selected_device,
            "failures": normalized,
            "failure_count": len(normalized),
            "fetched_at": _now_iso(),
            "authoritative_source": "laravel.command_failures_projection",
            "redactions": ["sensitive_result_payloads_stripped"],
        }

    def _search_audit_events(
        self,
        payload: ChatAskRequest,
        selected_device: str,
        allowed_devices: set[str],
    ) -> dict[str, Any]:
        if selected_device not in allowed_devices:
            return self._blocked_result("search_audit_events")
        entries = payload.context.audit_events or []
        events = []
        for row in entries[:50]:
            events.append(
                {
                    "audit_id": row.get("id"),
                    "event_type": row.get("event_type"),
                    "timestamp": row.get("timestamp"),
                    "device_id": row.get("device_id") or selected_device,
                    "actor_ref": row.get("actor"),
                    "correlation_id": row.get("source"),
                }
            )
        return {
            "events": events,
            "fetched_at": _now_iso(),
            "authoritative_source": "laravel.audit_trail",
            "redactions": ["request_metadata_redacted"],
        }

    def _get_system_health(self, payload: ChatAskRequest) -> dict[str, Any]:
        data = payload.context.system_health or {}
        return {
            "status": data.get("overall_status"),
            "components": data.get("components", []),
            "overview": {
                "component_counts": data.get("component_counts", {}),
                "pipeline": data.get("pipeline", {}),
                "webhooks": data.get("webhooks", {}),
            },
            "fetched_at": _now_iso(),
            "authoritative_source": "laravel.system_health_projection",
            "redactions": ["infra_hostnames_redacted"],
        }

    def _blocked_result(self, tool_name: str) -> dict[str, Any]:
        return {
            "error": "blocked",
            "tool_name": tool_name,
            "fetched_at": _now_iso(),
            "authoritative_source": "sidecar.guardrail",
            "redactions": [],
        }

    def _error_result(self, tool_name: str) -> dict[str, Any]:
        return {
            "error": "tool_error",
            "tool_name": tool_name,
            "fetched_at": _now_iso(),
            "authoritative_source": "sidecar.tool_router",
            "redactions": [],
        }

    def _estimate_rows(self, tool_name: str, result: dict[str, Any]) -> int:
        if tool_name == "get_command_failures":
            rows = result.get("failures")
            return len(rows) if isinstance(rows, list) else 0
        if tool_name == "search_audit_events":
            rows = result.get("events")
            return len(rows) if isinstance(rows, list) else 0
        return 1

    def _excerpt(self, tool_name: str, result: dict[str, Any]) -> str:
        if tool_name == "get_device_summary":
            return f"Device state={result.get('lifecycle_state')} risk={result.get('risk_score')}"
        if tool_name == "get_latest_telemetry":
            metrics = result.get("metrics", {})
            return f"Telemetry cpu={metrics.get('cpu')} ram={metrics.get('ram')}"
        if tool_name == "get_command_failures":
            return f"Failures={result.get('failure_count', 0)}"
        if tool_name == "search_audit_events":
            events = result.get("events", [])
            latest = events[0].get("event_type") if isinstance(events, list) and events else "none"
            return f"Audit events={len(events) if isinstance(events, list) else 0} latest={latest}"
        if tool_name == "get_system_health":
            return f"System health status={result.get('status')}"
        return tool_name

    def _evidence_uri(self, tool_name: str, selected_device: str) -> str:
        if tool_name == "get_device_summary":
            return f"/devices/{selected_device}"
        if tool_name == "get_latest_telemetry":
            return f"/devices/{selected_device}/telemetry/latest"
        if tool_name == "get_command_failures":
            return f"/devices/{selected_device}/commands"
        if tool_name == "search_audit_events":
            return f"/audit/events?device_id={selected_device}"
        if tool_name == "get_system_health":
            return "/system-health/overview"
        return "/"
