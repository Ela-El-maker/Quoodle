import uuid
from typing import Any, Dict

from fastapi import APIRouter, HTTPException

from app.config import settings
from app.ws.connection_manager import ConnectionManager
from app.ws.protocol import iso_timestamp, compute_sig

policy_state: Dict[str, Any] = {
    "policy_version": "policy-placeholder",
    "policy_hash": settings.policy_hash,
    "policy_url": None,
    "effective_from": iso_timestamp(),
}


def build_command_delivery(payload: Dict[str, Any], session_id: str) -> Dict[str, Any]:
    envelope = payload.get("envelope", {})
    device_id = payload["device_id"]
    header = envelope.get("header", {})
    body = envelope.get("body", {})
    meta = envelope.get("meta", {})
    command_message_id = payload.get("command_id", str(uuid.uuid4()))
    trace_id = payload.get("trace_id", str(uuid.uuid4()))
    command_envelope = {
        "header": {
            "version": header.get("version", "1.1"),
            "timestamp": header.get("timestamp", iso_timestamp()),
            "ttl_seconds": header.get("ttl_seconds", 300),
            "priority": header.get("priority", "normal"),
            "requires_ack": header.get("requires_ack", True),
            "long_running": header.get("long_running", False),
        },
        "body": {
            "method": body.get("method", payload.get("method", "")),
            "params": body.get("params", payload.get("params", {})),
            "sensitive": body.get("sensitive", payload.get("sensitive", False)),
        },
        "meta": {
            "device_id": device_id,
            "origin_user_id": meta.get("origin_user_id", payload.get("origin_user_id", "user-unknown")),
            "enc": meta.get("enc", "none"),
            "enc_key_id": meta.get("enc_key_id"),
            "policy_version": meta.get("policy_version", payload.get("policy_version", "policy-placeholder")),
        },
        "message_id": command_message_id,
        "trace_id": trace_id,
        "seq": payload.get("seq", 1),
        "sig": envelope.get("sig"),
    }
    command_envelope["sig"] = command_envelope["sig"] or compute_sig(command_envelope)

    message = {
        "type": "COMMAND_DELIVERY",
        "from": settings.controller_id,
        "device_id": device_id,
        "message_id": f"m-cmd-delivery-{uuid.uuid4()}",
        "session_id": session_id,
        "timestamp": iso_timestamp(),
        "body": {
            "command_envelope": command_envelope
        },
    }
    message["sig"] = compute_sig(message)
    return message


def build_dispatch_response(status: str, device_id: str, command_id: str, reason: str | None = None) -> Dict[str, Any]:
    return {
        "status": status,
        "device_id": device_id,
        "command_id": command_id,
        "reason": reason,
    }


def create_router(manager: ConnectionManager) -> APIRouter:
    router = APIRouter(prefix="/api/v1")

    @router.post("/command/dispatch")
    async def dispatch_command(payload: Dict[str, Any]):
        required = ["command_id", "device_id", "trace_id", "seq", "envelope"]
        for field in required:
            if field not in payload:
                raise HTTPException(status_code=400, detail=f"Missing field {field}")

        device_id = payload["device_id"]
        entry = await manager.get(device_id)
        if not entry:
            return build_dispatch_response("device_offline", device_id, payload["command_id"], "device not connected")

        message = build_command_delivery(payload, entry.session_id)
        await entry.websocket.send_json(message)
        return build_dispatch_response("dispatched", device_id, payload["command_id"], None)

    @router.post("/policy/push")
    async def push_policy(payload: Dict[str, Any]):
        required = ["policy_version", "policy_hash", "policy_url", "signed_at", "signature"]
        for field in required:
            if field not in payload:
                raise HTTPException(status_code=400, detail=f"Missing field {field}")

        policy_state.update(
            {
                "policy_version": payload["policy_version"],
                "policy_hash": payload["policy_hash"],
                "policy_url": payload["policy_url"],
                "effective_from": payload.get("signed_at", iso_timestamp()),
            }
        )

        policy_msg = {
            "type": "POLICY_UPDATE",
            "from": settings.controller_id,
            "device_id": None,
            "message_id": f"m-policy-{uuid.uuid4()}",
            "session_id": None,
            "timestamp": iso_timestamp(),
            "body": {
                "policy_version": policy_state["policy_version"],
                "policy_hash": policy_state["policy_hash"],
                "policy_url": policy_state["policy_url"],
                "effective_from": policy_state["effective_from"],
            },
        }
        policy_msg["sig"] = compute_sig(policy_msg)

        for entry in await manager.all_entries():
            policy_msg["device_id"] = entry.device_id
            policy_msg["session_id"] = entry.session_id
            await entry.websocket.send_json(policy_msg)

        return {"status": "accepted", "reason": None}

    @router.post("/update/deploy")
    async def deploy_update(payload: Dict[str, Any]):
        required = [
            "release_id",
            "version",
            "manifest_url",
            "signature_url",
            "sha256",
            "min_os_build",
            "policy",
        ]
        for field in required:
            if field not in payload:
                raise HTTPException(status_code=400, detail=f"Missing field {field}")

        update_msg = {
            "type": "UPDATE_ANNOUNCE",
            "from": settings.controller_id,
            "device_id": None,
            "message_id": f"m-update-{uuid.uuid4()}",
            "session_id": None,
            "timestamp": iso_timestamp(),
            "body": {
                "release_id": payload["release_id"],
                "version": payload["version"],
                "manifest_url": payload["manifest_url"],
                "signature_url": payload["signature_url"],
                "sha256": payload["sha256"],
                "min_os_build": payload["min_os_build"],
                "policy": payload["policy"],
            },
        }
        update_msg["sig"] = compute_sig(update_msg)

        entries = await manager.all_entries()
        if not entries:
            return {"status": "queued", "reason": "no_devices_online"}

        for entry in entries:
            update_msg["device_id"] = entry.device_id
            update_msg["session_id"] = entry.session_id
            await entry.websocket.send_json(update_msg)

        return {"status": "broadcasted", "reason": None, "release_id": payload["release_id"]}

    return router
