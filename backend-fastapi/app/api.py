import uuid
from typing import Any, Dict

from fastapi import APIRouter, HTTPException

from app.api.schemas import (
    CommandDispatchRequest,
    PolicyPushRequest,
    OTAPublishRequest,
    QuarantineRequest,
)
from app.config import settings
from app.state import (
    event_bus,
    offline_queue,
    ota_manager,
    policy_resolver,
    quarantine_handler,
)
from app.ws.connection_manager import ConnectionManager
from app.ws.protocol import iso_timestamp, compute_sig


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
            "policy_version": meta.get("policy_version", payload.get("policy", {}).get("policy_version", "policy-placeholder")),
            "policy_hash": payload.get("policy", {}).get("policy_hash"),
            "compliance": payload.get("compliance"),
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

    @router.get("/devices/online")
    async def devices_online():
        entries = await manager.all_entries()
        return {
            "devices": [
                {
                    "device_id": e.device_id,
                    "session_id": e.session_id,
                    "agent_version": e.agent_version,
                    "os_build": e.os_build,
                    "attestation_hash": e.attestation_hash,
                    "connected_at": e.connected_at,
                    "quarantine": quarantine_handler.status(e.device_id),
                }
                for e in entries
            ]
        }

    @router.post("/command/dispatch")
    async def dispatch_command(payload: CommandDispatchRequest):
        device_id = payload.device_id

        if quarantine_handler.is_blocked(device_id, payload.method):
            return build_dispatch_response("blocked", device_id, payload.command_id, "device_quarantined")

        entry = await manager.get(device_id)
        if not entry:
            offline_queue.enqueue(device_id, payload.dict())
            return build_dispatch_response("queued_offline", device_id, payload.command_id, "device not connected")

        message = build_command_delivery(payload.dict(), entry.session_id)
        await entry.websocket.send_json(message)
        await event_bus.publish("commands.dispatched.v1", {"command_id": payload.command_id, "device_id": device_id})
        return build_dispatch_response("dispatched", device_id, payload.command_id, None)

    @router.post("/policy/push")
    async def push_policy(payload: PolicyPushRequest):
        current = policy_resolver.update(
            policy_version=payload.policy_version,
            policy_hash=payload.policy_hash,
            policy_url=payload.policy_url,
            signed_at=payload.signed_at,
            signature=payload.signature,
        )

        policy_msg = policy_resolver.build_message(None, None)
        entries = await manager.all_entries()
        for entry in entries:
            policy_msg["device_id"] = entry.device_id
            policy_msg["session_id"] = entry.session_id
            await entry.websocket.send_json(policy_msg)

        await event_bus.publish("policy.updated.v1", current)
        return {"status": "accepted", "reason": None, "policy": current}

    @router.get("/policy/state")
    async def policy_state():
        return policy_resolver.current()

    @router.post("/update/deploy")
    async def deploy_update(payload: OTAPublishRequest):
        manifest = {
            "release_id": payload.release_id,
            "version": payload.version,
            "manifest_url": payload.manifest_url,
            "signature_url": payload.signature_url,
            "sha256": payload.sha256,
            "min_os_build": payload.min_os_build,
            "policy": payload.policy,
        }
        ota_manager.set_release(manifest)
        update_msg = ota_manager.build_announce(None, None)
        entries = await manager.all_entries()
        if not entries:
            return {"status": "queued", "reason": "no_devices_online"}

        for entry in entries:
            if not update_msg:
                continue
            update_msg["device_id"] = entry.device_id
            update_msg["session_id"] = entry.session_id
            await entry.websocket.send_json(update_msg)

        await event_bus.publish("ota.release.announced.v1", manifest)
        return {"status": "broadcasted", "reason": None, "release_id": payload.release_id}

    @router.post("/admin/quarantine/{device_id}")
    async def set_quarantine(device_id: str, payload: QuarantineRequest):
        quarantine_handler.set_quarantine(device_id, payload.reason)
        return {"status": "quarantined", "device_id": device_id, "reason": payload.reason, "allowlist": quarantine_handler.allowlist()}

    @router.delete("/admin/quarantine/{device_id}")
    async def lift_quarantine(device_id: str):
        quarantine_handler.lift_quarantine(device_id)
        return {"status": "cleared", "device_id": device_id}

    return router
