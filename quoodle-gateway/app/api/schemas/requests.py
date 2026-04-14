from typing import Any, Dict, Optional, List, Literal

from pydantic import BaseModel, Field, field_validator


class CommandDispatchRequest(BaseModel):
    command_id: str
    device_id: str
    trace_id: str
    seq: int
    method: str
    params: Dict[str, Any] = Field(default_factory=dict)
    sensitive: bool = False
    envelope: Dict[str, Any]
    policy: Optional[Dict[str, Any]] = None
    compliance: Optional[Dict[str, Any]] = None

    @field_validator("method")
    def method_not_empty(cls, v: str) -> str:
        if not v:
            raise ValueError("method required")
        return v


class AppLockRule(BaseModel):
    rule_id: str
    match_type: Literal["basename", "full_path"]
    value: str
    action: Literal["block"] = "block"
    priority: int = 1000
    expires_at: Optional[str] = None

    @field_validator("rule_id", "value")
    def non_empty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("required")
        return v.strip()

    @field_validator("priority")
    def priority_bounds(cls, v: int) -> int:
        if v < 1 or v > 999999:
            raise ValueError("priority_out_of_range")
        return v


class AppLockPolicyBundle(BaseModel):
    enabled: bool = False
    mode: Literal["blocklist"] = "blocklist"
    fail_mode: Literal["open"] = "open"
    policy_version: str
    policy_hash: str
    event_dedupe_sec: int = 30
    updated_at: Optional[str] = None
    rules: List[AppLockRule] = Field(default_factory=list)

    @field_validator("event_dedupe_sec")
    def dedupe_bounds(cls, v: int) -> int:
        if v < 1 or v > 3600:
            raise ValueError("event_dedupe_sec_out_of_range")
        return v


class PolicyPushRequest(BaseModel):
    policy_version: str
    policy_hash: str
    policy_url: str
    signed_at: str
    signature: str
    app_lock: Optional[AppLockPolicyBundle] = None
    target_device_ids: Optional[List[str]] = None

    @field_validator("target_device_ids")
    def validate_target_device_ids(cls, v: Optional[List[str]]) -> Optional[List[str]]:
        if v is None:
            return None
        normalized = [item.strip() for item in v if isinstance(item, str) and item.strip()]
        if len(normalized) == 0:
            return None
        if len(normalized) > 1000:
            raise ValueError("target_device_ids_too_many")
        return normalized


class OTAPublishRequest(BaseModel):
    release_id: str
    version: str
    manifest_url: str
    signature_url: str
    sha256: str
    min_os_build: str
    policy: Dict[str, Any]


class QuarantineRequest(BaseModel):
    reason: str


class DevicePairedRequest(BaseModel):
    device_id: str
    device_name: str
    user_id: str
    ed25519_pubkey_b64: str
    policy_hash: str
    policy_version: str
    paired_at: str
    agent_jwt: str | None = None
    agent_jwt_expires_at: str | None = None


class TelemetryHeartbeatRequest(BaseModel):
    schema_version: str = "v1"
    device_id: str
    session_id: str
    timestamp: str
    seq: int
    telemetry_scope: str = "telemetry_extended"
    metrics: Dict[str, Any] = Field(default_factory=dict)
    policy_hash: Optional[str] = None
    machine_secret_hash: Optional[str] = None
    masked_fields: List[str] = Field(default_factory=list)

    @field_validator("schema_version")
    def schema_supported(cls, v: str) -> str:
        if v != "v1":
            raise ValueError("unsupported_schema_version")
        return v

    @field_validator("telemetry_scope")
    def scope_supported(cls, v: str) -> str:
        if v not in {"telemetry_basic", "telemetry_extended", "kernel_event"}:
            raise ValueError("unsupported_telemetry_scope")
        return v

    @field_validator("seq")
    def seq_positive(cls, v: int) -> int:
        if v < 1:
            raise ValueError("seq_must_be_positive")
        return v


class TelemetryBatchRequest(BaseModel):
    device_id: str
    entries: List[TelemetryHeartbeatRequest] = Field(default_factory=list)

    @field_validator("entries")
    def entries_not_empty(cls, v: List[TelemetryHeartbeatRequest]) -> List[TelemetryHeartbeatRequest]:
        if not v:
            raise ValueError("entries_required")
        if len(v) > 200:
            raise ValueError("entries_too_many")
        return v
