import uuid
from datetime import datetime, timezone
from typing import Any, Dict

from app.config import settings


def iso_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def validate_auth_envelope(payload: Dict[str, Any]) -> Dict[str, Any]:
    required_fields = ["type", "from", "device_id", "message_id", "body", "sig"]
    for field in required_fields:
        if field not in payload:
            raise ValueError(f"Missing required field: {field}")

    if payload.get("type") != "AUTH":
        raise ValueError("First message must be AUTH")
    if payload.get("from") != "agent":
        raise ValueError("AUTH must originate from agent")

    body = payload.get("body") or {}
    if "auth" not in body or "jwt" not in body.get("auth", {}) or "nonce" not in body.get("auth", {}):
        raise ValueError("AUTH body.auth.jwt and nonce required")
    if "agent_info" not in body:
        raise ValueError("AUTH body.agent_info required")

    return payload


def build_auth_ack(device_id: str, session_id: str) -> Dict[str, Any]:
    return {
        "type": "AUTH_ACK",
        "from": settings.controller_id,
        "device_id": device_id,
        "message_id": f"m-auth-ack-{uuid.uuid4()}",
        "session_id": session_id,
        "timestamp": iso_timestamp(),
        "sig": "controller-sig-placeholder",
        "body": {
            "status": "ok",
            "session_id": session_id,
            "heartbeat_interval_seconds": settings.heartbeat_interval_seconds,
            "telemetry_interval_seconds": settings.telemetry_interval_seconds,
            "policy_hash": settings.policy_hash,
        },
    }


def build_auth_error(device_id: str, error_code: str, error_message: str) -> Dict[str, Any]:
    return {
        "type": "AUTH_ERROR",
        "from": settings.controller_id,
        "device_id": device_id,
        "message_id": f"m-auth-err-{uuid.uuid4()}",
        "session_id": None,
        "timestamp": iso_timestamp(),
        "sig": "controller-sig-placeholder",
        "body": {
            "status": "error",
            "error_code": error_code,
            "error_message": error_message,
        },
    }
