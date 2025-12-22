import uuid
from datetime import datetime, timezone
from typing import Any, Dict

from app.config import settings
import hashlib
import os
import base64
from app.ws.canonical import canonicalize_json, strip_sig
try:
    from nacl.signing import SigningKey
    HAVE_PYNACL = True
except Exception:
    HAVE_PYNACL = False

try:
    from app.utils.dpapi_loader import load_dpapi_blob_to_b64
except Exception:
    load_dpapi_blob_to_b64 = None


def iso_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def compute_sig(payload: Dict[str, Any]) -> str:
    canonical = canonicalize_json(strip_sig(payload))
    # Prefer Ed25519 signing when PyNaCl and a signing key are available.
    if HAVE_PYNACL:
        sk_b64 = os.getenv("ED25519_PRIVATE_KEY_B64")
        # try file
        if not sk_b64:
            p = os.getenv("ED25519_PRIVATE_KEY_PATH")
            if p and os.path.exists(p):
                try:
                    with open(p, "rb") as f:
                        sk_b64 = f.read().decode().strip()
                except Exception:
                    sk_b64 = None
        # try DPAPI
        if not sk_b64 and load_dpapi_blob_to_b64:
            try:
                sk_b64 = load_dpapi_blob_to_b64("ED25519_PRIVATE_KEY_DPAPI_B64", "ED25519_PRIVATE_KEY_DPAPI_PATH")
            except Exception:
                sk_b64 = None

        if sk_b64:
            try:
                sk_bytes = base64.b64decode(sk_b64)
                if len(sk_bytes) == 64:
                    seed = sk_bytes[:32]
                elif len(sk_bytes) == 32:
                    seed = sk_bytes
                else:
                    seed = None
                if seed:
                    signer = SigningKey(seed)
                    signed = signer.sign(canonical)
                    sig = signed.signature
                    return base64.b64encode(sig).decode()
            except Exception:
                pass

    if settings.require_ed25519 and not settings.allow_dev_sig_fallback:
        raise RuntimeError("Ed25519 signing required but PyNaCl/key not available")

    # fallback deterministic signature
    return hashlib.sha256(canonical).hexdigest()


def validate_auth_envelope(payload: Dict[str, Any]) -> Dict[str, Any]:
    required_fields = ["type", "from", "device_id", "message_id", "body", "sig", "timestamp", "session_id"]
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
    payload = {
        "type": "AUTH_ACK",
        "from": settings.controller_id,
        "device_id": device_id,
        "message_id": f"m-auth-ack-{uuid.uuid4()}",
        "session_id": session_id,
        "timestamp": iso_timestamp(),
        "body": {
            "status": "ok",
            "session_id": session_id,
            "heartbeat_interval_seconds": settings.heartbeat_interval_seconds,
            "telemetry_interval_seconds": settings.telemetry_interval_seconds,
            "policy_hash": settings.policy_hash,
        },
    }
    payload["sig"] = compute_sig(payload)
    return payload


def build_auth_error(device_id: str, error_code: str, error_message: str) -> Dict[str, Any]:
    payload = {
        "type": "AUTH_ERROR",
        "from": settings.controller_id,
        "device_id": device_id,
        "message_id": f"m-auth-err-{uuid.uuid4()}",
        "session_id": None,
        "timestamp": iso_timestamp(),
        "body": {
            "status": "error",
            "error_code": error_code,
            "error_message": error_message,
        },
    }
    payload["sig"] = compute_sig(payload)
    return payload


def validate_heartbeat(payload: Dict[str, Any], expected_session: str) -> None:
    required_fields = ["type", "from", "device_id", "message_id", "body", "sig", "session_id", "timestamp"]
    for field in required_fields:
        if field not in payload:
            raise ValueError(f"Missing required field: {field}")
    if payload["type"] != "HEARTBEAT":
        raise ValueError("Invalid type for heartbeat")
    if payload["from"] != "agent":
        raise ValueError("Heartbeat must originate from agent")
    if not payload.get("session_id"):
        raise ValueError("Heartbeat requires session_id")
    if expected_session and payload.get("session_id") != expected_session:
        raise ValueError("Heartbeat session_id mismatch")

    body = payload.get("body") or {}
    if "status" not in body:
        raise ValueError("Heartbeat body.status required")


def validate_telemetry(payload: Dict[str, Any], expected_session: str) -> None:
    required_fields = ["type", "from", "device_id", "message_id", "body", "sig", "session_id", "timestamp"]
    for field in required_fields:
        if field not in payload:
            raise ValueError(f"Missing required field: {field}")
    if payload["type"] != "TELEMETRY":
        raise ValueError("Invalid type for telemetry")
    if payload["from"] != "agent":
        raise ValueError("Telemetry must originate from agent")
    if not payload.get("session_id"):
        raise ValueError("Telemetry requires session_id")
    if expected_session and payload.get("session_id") != expected_session:
        raise ValueError("Telemetry session_id mismatch")

    body = payload.get("body") or {}
    if "metrics" not in body or "telemetry_scope" not in body or "timestamp" not in body:
        raise ValueError("Telemetry body missing required fields")
    metrics = body.get("metrics") or {}
    for field in ["cpu", "ram", "disk_usage", "network_tx", "network_rx"]:
        if field not in metrics:
            raise ValueError(f"Telemetry metrics missing {field}")


def validate_command_result(payload: Dict[str, Any], expected_session: str) -> None:
    required_fields = ["type", "from", "device_id", "message_id", "body", "sig", "session_id", "timestamp"]
    for field in required_fields:
        if field not in payload:
            raise ValueError(f"Missing required field: {field}")
    if payload["type"] != "COMMAND_RESULT":
        raise ValueError("Invalid type for command result")
    if payload["from"] != "agent":
        raise ValueError("Command result must originate from agent")
    if not payload.get("session_id"):
        raise ValueError("Command result requires session_id")
    if expected_session and payload.get("session_id") != expected_session:
        raise ValueError("Command result session_id mismatch")

    body = payload.get("body") or {}
    if "command_message_id" not in body or "execution_state" not in body or "result" not in body:
        raise ValueError("Command result body missing required fields")
    result = body.get("result") or {}
    if "status" not in result:
        raise ValueError("Command result missing status")


def validate_command_ack(payload: Dict[str, Any], expected_session: str) -> None:
    required_fields = ["type", "from", "device_id", "message_id", "body", "sig", "session_id", "timestamp"]
    for field in required_fields:
        if field not in payload:
            raise ValueError(f"Missing required field: {field}")
    if payload["type"] != "COMMAND_ACK":
        raise ValueError("Invalid type for command ack")
    if payload["from"] != "agent":
        raise ValueError("Command ack must originate from agent")
    if not payload.get("session_id"):
        raise ValueError("Command ack requires session_id")
    if expected_session and payload.get("session_id") != expected_session:
        raise ValueError("Command ack session_id mismatch")

    body = payload.get("body") or {}
    if "command_message_id" not in body or "status" not in body:
        raise ValueError("Command ack body missing required fields")
