from typing import Any, Dict, Optional

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


class PolicyPushRequest(BaseModel):
    policy_version: str
    policy_hash: str
    policy_url: str
    signed_at: str
    signature: str


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
