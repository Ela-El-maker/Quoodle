import asyncio
import json
import uuid

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from app.config import settings
from app.ws.auth import validate_auth_jwt
from app.ws.connection_manager import ConnectionManager
from app.ws.protocol import build_auth_ack, build_auth_error, validate_auth_envelope

app = FastAPI(title="Secure Device Control - FastAPI Controller")
manager = ConnectionManager()


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.websocket("/agent")
async def agent_ws(websocket: WebSocket):
    await websocket.accept()
    device_id = "unknown"
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

        try:
            claims = await validate_auth_jwt(auth_token)
        except Exception as exc:
            await websocket.send_json(build_auth_error(device_id, "AUTH_INVALID_JWT", str(exc)))
            await websocket.close(code=4401)
            return

        session_id = str(uuid.uuid4())
        await manager.register(device_id, websocket)

        auth_ack = build_auth_ack(device_id, session_id)
        await websocket.send_json(auth_ack)

        # Phase 2 ends after basic auth; keep the connection alive.
        while True:
            try:
                await websocket.receive_text()
            except WebSocketDisconnect:
                break
            except Exception:
                # Ignore non-AUTH messages in this phase.
                continue
    finally:
        await manager.unregister(device_id)
        try:
            await websocket.close()
        except Exception:
            pass
