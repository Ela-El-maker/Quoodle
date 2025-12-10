import asyncio
import json
import uuid

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from app.api import create_router
from app.config import settings
from app.ws.auth import validate_auth_jwt
from app.ws.connection_manager import ConnectionManager
from app.ws.protocol import (
    build_auth_ack,
    build_auth_error,
    iso_timestamp,
    validate_auth_envelope,
    validate_command_ack,
    validate_command_result,
    validate_heartbeat,
    validate_telemetry,
)
from app.ws.results import forward_command_result
from app.ws.webhooks import (
    fire_and_forget,
    forward_command_ack,
    forward_attestation,
    forward_telemetry_summary,
    notify_device_offline,
    notify_device_online,
)

app = FastAPI(title="Secure Device Control - FastAPI Controller")
manager = ConnectionManager()
app.include_router(create_router(manager))


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.websocket("/agent")
async def agent_ws(websocket: WebSocket):
    await websocket.accept()
    device_id = "unknown"
    session_id_assigned = None
    agent_info: dict[str, str] = {}
    try:
        raw = await websocket.receive_text()
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            await websocket.send_json(build_auth_error(device_id, "AUTH_INVALID_PAYLOAD", "Invalid JSON"))
            await websocket.close(code=4400)
            return

        try:
            validate_auth_envelope(payload)
        except ValueError as exc:
            await websocket.send_json(build_auth_error(device_id, "AUTH_INVALID_ENVELOPE", str(exc)))
            await websocket.close(code=4400)
            return

        device_id = payload.get("device_id", device_id)
        auth_token = payload["body"]["auth"]["jwt"]
        agent_info = payload["body"].get("agent_info", {})
        agent_info["connected_at"] = iso_timestamp()

        try:
            claims = await validate_auth_jwt(auth_token)
        except Exception as exc:
            await websocket.send_json(build_auth_error(device_id, "AUTH_INVALID_JWT", str(exc)))
            await websocket.close(code=4401)
            return

        session_id = str(uuid.uuid4())
        session_id_assigned = session_id
        await manager.register(
            device_id=device_id,
            websocket=websocket,
            session_id=session_id,
            agent_version=agent_info.get("agent_version"),
            os_build=agent_info.get("os_build"),
            attestation_hash=agent_info.get("attestation_hash"),
            connected_at=agent_info.get("connected_at"),
        )

        fire_and_forget(notify_device_online(device_id, session_id, agent_info))
        fire_and_forget(forward_attestation(device_id, iso_timestamp(), agent_info.get("attestation_hash")))

        auth_ack = build_auth_ack(device_id, session_id)
        await websocket.send_json(auth_ack)

        # Handle post-auth messages (Phase 4: heartbeat + telemetry)
        while True:
            try:
                incoming = await websocket.receive_text()
                try:
                    message = json.loads(incoming)
                except json.JSONDecodeError:
                    continue

                mtype = message.get("type")
                if mtype == "HEARTBEAT":
                    try:
                        validate_heartbeat(message, session_id_assigned)
                    except ValueError:
                        await websocket.close(code=4400)
                        break
                    continue
                if mtype == "TELEMETRY":
                    try:
                        validate_telemetry(message, session_id_assigned)
                    except ValueError:
                        await websocket.close(code=4400)
                        break
                    fire_and_forget(
                        forward_telemetry_summary(
                            device_id,
                            message.get("body", {}).get("metrics", {}),
                            message.get("timestamp", iso_timestamp()),
                        )
                    )
                    continue
                if mtype == "COMMAND_RESULT":
                    try:
                        validate_command_result(message, session_id_assigned)
                    except ValueError:
                        await websocket.close(code=4400)
                        break
                    await forward_command_result(message)
                    continue
                if mtype == "COMMAND_ACK":
                    try:
                        validate_command_ack(message, session_id_assigned)
                    except ValueError:
                        await websocket.close(code=4400)
                        break
                    fire_and_forget(
                        forward_command_ack(
                            message.get("body", {}),
                            device_id,
                            message.get("timestamp", iso_timestamp()),
                        )
                    )
                    continue
            except WebSocketDisconnect:
                break
            except Exception:
                continue
    finally:
        entry = await manager.unregister(device_id)
        fire_and_forget(
            notify_device_offline(
                device_id=device_id,
                session_id=entry.session_id if entry else session_id_assigned,
                last_seen=iso_timestamp(),
                reason="disconnect",
            )
        )
        try:
            await websocket.close()
        except Exception:
            pass
