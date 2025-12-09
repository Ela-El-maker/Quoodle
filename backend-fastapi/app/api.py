import uuid
from typing import Any, Dict

from fastapi import APIRouter, HTTPException

from app.config import settings
from app.ws.connection_manager import ConnectionManager
from app.ws.protocol import iso_timestamp


def build_command_delivery(payload: Dict[str, Any], session_id: str) -> Dict[str, Any]:
    envelope = payload.get("envelope", {})
    device_id = payload["device_id"]
    return {
        "type": "COMMAND_DELIVERY",
        "from": settings.controller_id,
        "device_id": device_id,
        "message_id": f"m-cmd-delivery-{uuid.uuid4()}",
        "session_id": session_id,
        "timestamp": iso_timestamp(),
        "sig": "controller-sig-placeholder",
        "body": {
            "command_envelope": {
                "header": envelope.get(
                    "header",
                    {
                        "version": "1.1",
                        "timestamp": iso_timestamp(),
                        "ttl_seconds": 300,
                        "priority": "normal",
                        "requires_ack": True,
                        "long_running": False,
                    },
                ),
                "body": envelope.get(
                    "body",
                    {
                        "method": payload.get("method", ""),
                        "params": payload.get("params", {}),
                        "sensitive": payload.get("sensitive", False),
                    },
                ),
                "meta": envelope.get(
                    "meta",
                    {
                        "origin_user_id": payload.get("origin_user_id", "user-unknown"),
                        "enc": "none",
                        "enc_key_id": None,
                        "policy_version": payload.get("policy_version", "policy-placeholder"),
                        "device_id": device_id,
                    },
                ),
                "message_id": payload.get("command_id", str(uuid.uuid4())),
                "trace_id": payload.get("trace_id", str(uuid.uuid4())),
                "seq": payload.get("seq", 1),
                "sig": envelope.get("sig", "controller-envelope-sig-placeholder"),
            }
        },
    }


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
        required = ["command_id", "device_id"]
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

    return router
