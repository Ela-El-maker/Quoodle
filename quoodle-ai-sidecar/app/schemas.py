from __future__ import annotations

from typing import Any, Literal
from pydantic import BaseModel, Field


class ActorContext(BaseModel):
    tenant_id: str = "default"
    actor_id: str
    role: str
    session_id: str | None = None


class ScopeContext(BaseModel):
    allowed_device_ids: list[str] = Field(default_factory=list)
    allowed_actions: list[str] = Field(default_factory=list)
    expires_at: str | None = None


class SelectedRefs(BaseModel):
    device_id: str


class ContextBundle(BaseModel):
    device_summary: dict[str, Any] | None = None
    latest_telemetry: dict[str, Any] | None = None
    command_failures: list[dict[str, Any]] = Field(default_factory=list)
    audit_events: list[dict[str, Any]] = Field(default_factory=list)
    system_health: dict[str, Any] | None = None


class ChatAskRequest(BaseModel):
    conversation_id: str | None = None
    query: str = Field(min_length=1, max_length=5000)
    actor_context: ActorContext
    scope_context: ScopeContext
    selected_refs: SelectedRefs
    ui_surface: str | None = None
    correlation_id: str
    context: ContextBundle


class ChatAskResponse(BaseModel):
    status: Literal["ok", "degraded", "incomplete"]
    assistant_message: str
    confidence: dict[str, Any]
    freshness_seconds: int | None = None
    evidence_refs: list[dict[str, Any]]
    artifact: dict[str, Any]
    tool_calls: list[dict[str, Any]]
    model_call: dict[str, Any]
    guardrail_events: list[dict[str, Any]]

