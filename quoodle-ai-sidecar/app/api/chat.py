from __future__ import annotations

import time
from typing import Any

from fastapi import APIRouter, HTTPException, Request

from app.core.auth import verify_service_auth
from app.core.config import settings
from app.core.hashing import sha256_json, sha256_text
from app.guardrails.checks import (
    derive_artifact_quality,
    derive_next_safe_questions,
    enforce_output_contract,
    post_model_check,
    pre_prompt_check,
)
from app.model.model_router import ModelRouter
from app.observability.metrics import metrics
from app.schemas import ChatAskRequest, ChatAskResponse
from app.tools.router import ToolRouter

router = APIRouter(prefix="/internal/ai/chat")


def _confidence(tool_calls: list[dict[str, Any]], degraded: bool) -> dict[str, Any]:
    total = len(tool_calls)
    ok = len([c for c in tool_calls if c.get("status") == "ok"])
    score = 0.4
    if total > 0:
        score += (ok / total) * 0.5
    if degraded:
        score -= 0.2
    score = max(0.0, min(score, 1.0))
    if score >= 0.75:
        band = "high"
    elif score >= 0.5:
        band = "medium"
    else:
        band = "low"
    return {
        "score": round(score, 4),
        "band": band,
        "basis": ["tool_success_rate", "provider_health"],
    }


@router.post("/ask", response_model=ChatAskResponse)
async def ask(payload: ChatAskRequest, request: Request) -> dict[str, Any]:
    started_at = time.perf_counter()

    def elapsed_ms() -> int:
        return int((time.perf_counter() - started_at) * 1000)

    verify_service_auth(request)

    if not settings.ai_global_enabled or not settings.ai_device_copilot_enabled:
        metrics.record_request("disabled", elapsed_ms())
        raise HTTPException(
            status_code=503,
            detail={"code": "ai_disabled", "message": "Device Copilot is disabled"},
        )

    guardrail_events: list[dict[str, Any]] = []
    pre_events, violation = pre_prompt_check(payload)
    guardrail_events.extend(pre_events)
    if violation == "scope_violation":
        metrics.record_guardrail_block()
        metrics.record_request("scope_blocked", elapsed_ms())
        raise HTTPException(
            status_code=403,
            detail={"code": "scope_unresolved", "message": "Requested device is outside actor scope"},
        )
    if violation:
        metrics.record_guardrail_block()
        metrics.record_request("invalid", elapsed_ms())
        raise HTTPException(
            status_code=422,
            detail={"code": "invalid_query", "message": "Query must not be empty"},
        )

    tool_router = ToolRouter()
    tool_result = await tool_router.run(payload)
    guardrail_events.extend(tool_result.guardrail_events)
    for tool_log in tool_result.tool_calls:
        metrics.record_tool(
            str(tool_log.get("tool_name")),
            str(tool_log.get("status")),
            tool_log.get("duration_ms") if isinstance(tool_log.get("duration_ms"), int) else None,
        )

    model_router = ModelRouter()
    model_result = await model_router.generate(
        payload.query,
        payload.context.model_dump(),
        tool_result.tool_outputs,
        payload.correlation_id,
    )
    metrics.record_model(
        model_result.status,
        model_result.latency_ms,
        model_result.input_tokens,
        model_result.output_tokens,
    )

    if model_result.degraded:
        guardrail_events.append(
            {
                "event_type": "model.degraded",
                "severity": "warning",
                "detail": {"error_code": model_result.error_code or "provider_degraded"},
            }
        )

    assistant_message, post_events = post_model_check(model_result.text)
    guardrail_events.extend(post_events)

    confidence = _confidence(tool_result.tool_calls, model_result.degraded)
    artifact_state, missing_information = derive_artifact_quality(
        tool_result.tool_calls,
        tool_result.tool_outputs,
        tool_result.freshness_seconds,
        confidence,
    )
    next_safe_questions = derive_next_safe_questions(assistant_message, missing_information)
    artifact = enforce_output_contract(
        assistant_message,
        tool_result.evidence_refs,
        confidence,
        artifact_state,
        missing_information,
        next_safe_questions,
    )
    metrics.record_artifact(str(artifact.get("artifact_type", "answer")))
    status = "incomplete" if artifact_state == "incomplete" else ("degraded" if model_result.degraded else "ok")
    if artifact_state == "incomplete":
        guardrail_events.append(
            {
                "event_type": "artifact.incomplete",
                "severity": "warning",
                "detail": {
                    "reason": "missing_context",
                    "missing_information": missing_information,
                },
            }
        )

    tool_call_set_hash = sha256_json(
        [
            {
                "tool_name": x.get("tool_name"),
                "status": x.get("status"),
                "output_hash": x.get("output_hash"),
            }
            for x in tool_result.tool_calls
        ]
    )
    model_call = {
        "provider": model_result.provider,
        "model": model_result.model,
        "api_mode": model_result.api_mode,
        "provider_response_id": model_result.response_id,
        "request_hash": model_result.request_hash,
        "tool_call_set_hash": tool_call_set_hash,
        "input_tokens": model_result.input_tokens,
        "output_tokens": model_result.output_tokens,
        "latency_ms": model_result.latency_ms,
        "status": model_result.status,
        "error_code": model_result.error_code,
        "prompt_id": model_result.prompt_id,
        "prompt_version": model_result.prompt_version,
        "prompt_source": model_result.prompt_source,
        "prompt_hash": model_result.prompt_hash,
    }
    metrics.record_request(status, elapsed_ms())

    return {
        "status": status,
        "assistant_message": assistant_message,
        "confidence": confidence,
        "freshness_seconds": tool_result.freshness_seconds,
        "evidence_refs": tool_result.evidence_refs,
        "artifact": {
            **artifact,
            "prompt_hash": model_result.prompt_hash or sha256_text(payload.query),
            "tool_call_set_hash": tool_call_set_hash,
        },
        "tool_calls": tool_result.tool_calls,
        "model_call": model_call,
        "guardrail_events": guardrail_events,
    }
