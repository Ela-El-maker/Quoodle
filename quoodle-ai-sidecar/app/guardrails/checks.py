from __future__ import annotations

import re
from typing import Any

from app.schemas import ChatAskRequest


def pre_prompt_check(payload: ChatAskRequest) -> tuple[list[dict[str, Any]], str | None]:
    events: list[dict[str, Any]] = []
    query = payload.query.strip()
    if query == "":
        events.append(
            {
                "event_type": "guardrail.precheck",
                "severity": "warning",
                "detail": {"reason": "empty_query"},
            }
        )
        return events, "invalid_query"

    selected_device_id = payload.selected_refs.device_id.strip()
    allowed = {x.strip() for x in payload.scope_context.allowed_device_ids if x.strip()}
    if selected_device_id == "" or selected_device_id not in allowed:
        events.append(
            {
                "event_type": "guardrail.scope",
                "severity": "critical",
                "detail": {
                    "reason": "device_scope_violation",
                    "selected_device_id": payload.selected_refs.device_id,
                },
            }
        )
        return events, "scope_violation"

    events.append(
        {
            "event_type": "guardrail.precheck",
            "severity": "info",
            "detail": {"result": "ok"},
        }
    )
    return events, None


def post_model_check(text: str) -> tuple[str, list[dict[str, Any]]]:
    events: list[dict[str, Any]] = []
    normalized = text.strip()
    if normalized == "":
        normalized = "I could not determine a confident answer from the available evidence."
        events.append(
            {
                "event_type": "guardrail.post_model",
                "severity": "warning",
                "detail": {"reason": "empty_model_output"},
            }
        )

    lowered = normalized.lower()
    risky_markers = ["executed command", "dispatched command", "run now", "auto-approve"]
    if any(marker in lowered for marker in risky_markers):
        normalized = (
            "Evidence analyzed. No action was executed by Copilot. "
            "Review deterministic command history before taking action."
        )
        events.append(
            {
                "event_type": "guardrail.post_model",
                "severity": "warning",
                "detail": {"reason": "unsafe_action_language_removed"},
            }
        )
    else:
        events.append(
            {
                "event_type": "guardrail.post_model",
                "severity": "info",
                "detail": {"result": "ok"},
            }
        )

    return normalized, events


def derive_artifact_quality(
    tool_calls: list[dict[str, Any]],
    tool_outputs: dict[str, dict[str, Any]],
    freshness_seconds: int | None,
    confidence: dict[str, Any],
) -> tuple[str, list[str]]:
    status_by_tool: dict[str, str] = {}
    for row in tool_calls:
        name = str(row.get("tool_name") or "").strip()
        if name == "":
            continue
        status_by_tool[name] = str(row.get("status") or "error").strip().lower()

    missing: list[str] = []
    critical_reasons: list[str] = []

    def add(reason: str, critical: bool = False) -> None:
        if reason not in missing:
            missing.append(reason)
        if critical and reason not in critical_reasons:
            critical_reasons.append(reason)

    # Required tools for Phase 1 Device Health Copilot quality.
    for tool_name, label in (
        ("get_device_summary", "Device summary could not be retrieved."),
        ("get_latest_telemetry", "Latest telemetry could not be retrieved."),
    ):
        if status_by_tool.get(tool_name) != "ok":
            add(label, critical=True)

    # Helpful but not strictly blocking tools.
    if status_by_tool.get("get_command_failures") not in {"", "ok"}:
        add("Recent command failure context is unavailable.")
    if status_by_tool.get("search_audit_events") not in {"", "ok"}:
        add("Recent audit event context is unavailable.")
    if status_by_tool.get("get_system_health") not in {"", "ok"}:
        add("System health context is unavailable.")

    device_summary = tool_outputs.get("get_device_summary") or {}
    if not isinstance(device_summary, dict):
        device_summary = {}

    if str(device_summary.get("device_id") or "").strip() == "":
        add("Device identity context is missing.", critical=True)
    if str(device_summary.get("lifecycle_state") or "").strip() == "":
        add("Device lifecycle state is unavailable.", critical=True)
    if device_summary.get("risk_score") is None:
        add("Device risk score is unavailable.")

    latest_telemetry = tool_outputs.get("get_latest_telemetry") or {}
    if not isinstance(latest_telemetry, dict):
        latest_telemetry = {}
    if str(latest_telemetry.get("timestamp") or "").strip() == "":
        add("Latest telemetry timestamp is unavailable.", critical=True)

    metrics = latest_telemetry.get("metrics")
    if not isinstance(metrics, dict):
        metrics = {}
    core_metric_values = [metrics.get("cpu"), metrics.get("ram"), metrics.get("disk_usage")]
    if all(value is None for value in core_metric_values):
        add("Core telemetry metrics (CPU, RAM, disk) are unavailable.", critical=True)

    if freshness_seconds is None:
        add("Data freshness could not be determined.", critical=True)
    elif freshness_seconds > 900:
        add("Context may be stale (older than 15 minutes).")

    confidence_score = confidence.get("score")
    numeric_confidence = confidence_score if isinstance(confidence_score, (int, float)) else None
    if numeric_confidence is not None and numeric_confidence < 0.5:
        add("Confidence is reduced due to limited successful evidence collection.", critical=True)

    state = "incomplete" if len(critical_reasons) > 0 else "created"
    return state, missing


def derive_next_safe_questions(message: str, missing_information: list[str]) -> list[str]:
    extracted: list[str] = []
    for match in re.findall(r"([A-Z][^?\n]{6,}\?)", message):
        cleaned = re.sub(r"\s+", " ", match).strip().strip("\"'`")
        if cleaned and cleaned not in extracted:
            extracted.append(cleaned)

    if extracted:
        return extracted[:3]

    suggestions: list[str] = []

    def push(value: str) -> None:
        if value not in suggestions:
            suggestions.append(value)

    text = " ".join(missing_information).lower()
    if "telemetry" in text:
        push("Can you show the latest telemetry sample and timestamp for this device?")
    if "command failure" in text:
        push("Can you list the last failed commands and their error codes for this device?")
    if "audit" in text:
        push("Can you show related audit events for this device in the last hour?")
    if "system health" in text:
        push("Is control-plane or gateway health degraded right now for this tenant?")

    push("What changed in the last hour for this device?")
    push("Which signals reduce confidence in this assessment?")
    return suggestions[:3]


def enforce_output_contract(
    message: str,
    evidence_refs: list[dict[str, Any]],
    confidence: dict[str, Any],
    state: str,
    missing_information: list[str],
    next_safe_questions: list[str],
) -> dict[str, Any]:
    return {
        "artifact_type": "answer",
        "state": state,
        "draft_only": False,
        "answer_class": "explanation",
        "summary": message,
        "confidence": confidence,
        "evidence_count": len(evidence_refs),
        "missing_information": missing_information,
        "next_safe_questions": next_safe_questions,
    }
