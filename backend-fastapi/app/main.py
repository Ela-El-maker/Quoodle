import asyncio
import json
import uuid

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from app.api_controller import create_router, build_command_delivery
from app.config import settings
from app.state import manager, offline_queue, ota_manager, policy_resolver, risk_scorer
from app.ws.auth import validate_auth_jwt
from app.services.device_registry import DeviceKeyRegistry, DeviceKeyRegistryConfig
from app.services.replay_protection import ReplayProtector, ReplayConfig, ReplayError, extract_seq_from_message
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
from app.ws.signing import verify_ed25519_signature, SignatureError
from app.ws.results import forward_command_result
from app.ws.webhooks import (
    fire_and_forget,
    forward_command_ack,
    forward_attestation,
    forward_telemetry_summary,
    notify_device_offline,
    notify_device_online,
)
from app.middleware.laravel_signature import LaravelSignatureMiddleware

app = FastAPI(title="Secure Device Control - FastAPI Controller")
app.add_middleware(LaravelSignatureMiddleware)
app.include_router(create_router(manager))

device_registry = DeviceKeyRegistry(
    DeviceKeyRegistryConfig(
        db_path=settings.device_registry_db_path,
        seed_json_path=settings.device_pubkeys_seed_path,
    )
)

replay = ReplayProtector(
    ReplayConfig(
        redis_url=settings.redis_url,
        max_clock_skew_seconds=settings.max_clock_skew_seconds,
        require_seq=settings.require_agent_seq,
        key_namespace="agent",
    )
)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.websocket("/agent")
async def agent_ws(websocket: WebSocket):
    await websocket.accept()
    device_id = "unknown"
    session_id_assigned = None
    agent_info: dict[str, str] = {}
    agent_pubkey_b64: str | None = None
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

        # Load device public key for signature verification.
        agent_pubkey_b64 = device_registry.get_pubkey_b64(device_id)
        if not agent_pubkey_b64:
            await websocket.send_json(build_auth_error(device_id, "AUTH_UNKNOWN_DEVICE", "Unknown device_id"))
            await websocket.close(code=4401)
            return

        # Replay and signature checks must occur before trusting AUTH body.
        try:
            replay.validate_timestamp(payload.get("timestamp", ""))
            nonce = payload.get("body", {}).get("auth", {}).get("nonce")
            if isinstance(nonce, str):
                await replay.check_and_store_nonce(device_id, nonce)
            verify_ed25519_signature(payload, agent_pubkey_b64)
        except (ReplayError, SignatureError):
            await websocket.close(code=4401)
            return

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
            agent_pubkey_b64=agent_pubkey_b64,
        )

        fire_and_forget(notify_device_online(device_id, session_id, agent_info))
        fire_and_forget(forward_attestation(device_id, iso_timestamp(), agent_info.get("attestation_hash")))

        auth_ack = build_auth_ack(device_id, session_id)
        await websocket.send_json(auth_ack)

        # Send latest policy/OTA and any queued commands
        await policy_resolver.send_current(websocket, device_id, session_id)
        await ota_manager.send_latest(websocket, device_id, session_id)
        for queued in offline_queue.drain(device_id):
            message = build_command_delivery(queued, session_id)
            await websocket.send_json(message)

        # Handle post-auth messages (Phase 4: heartbeat + telemetry)
        while True:
            try:
                incoming = await websocket.receive_text()
                try:
                    message = json.loads(incoming)
                except json.JSONDecodeError:
                    continue

                # Mandatory security checks for every inbound message.
                try:
                    replay.validate_timestamp(message.get("timestamp", ""))
                    await replay.check_and_update_seq(device_id, extract_seq_from_message(message))
                    if agent_pubkey_b64 is None:
                        raise SignatureError("Missing cached pubkey")
                    verify_ed25519_signature(message, agent_pubkey_b64)
                except (ReplayError, SignatureError):
                    await websocket.close(code=4401)
                    break

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
                    metrics = message.get("body", {}).get("metrics", {})
                    risk = risk_scorer.score(metrics)
                    fire_and_forget(
                        forward_telemetry_summary(
                            device_id,
                            metrics,
                            message.get("timestamp", iso_timestamp()),
                            risk_score=risk,
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
