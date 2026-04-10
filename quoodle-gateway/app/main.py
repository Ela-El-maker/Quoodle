import asyncio
import json
import logging
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from app.api_controller import create_router, build_command_delivery
from app.config import settings
from app.state import manager, offline_queue, ota_manager, policy_resolver, risk_scorer, eventbus, presence, webhook_outbox
from app.ws.auth import validate_auth_jwt
from app.services.device_registry import DeviceKeyRegistry, DeviceKeyRegistryConfig
from app.services.redis_service import RedisConfig, init_redis, close_redis, get_redis_service
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
    notify_device_activated,
    notify_device_offline,
    notify_device_online,
)
from app.middleware.laravel_signature import LaravelSignatureMiddleware

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager for startup/shutdown."""
    # Startup
    logger.info("Starting FastAPI gateway...")

    if not settings.policy_hash or not settings.policy_version:
        raise RuntimeError("POLICY_HASH and POLICY_VERSION must be configured")

    # Initialize Redis connection
    redis_config = RedisConfig(
        url=settings.redis_url,
        max_connections=settings.redis_max_connections,
        socket_timeout=settings.redis_socket_timeout,
        key_prefix=settings.redis_key_prefix,
    )
    redis = await init_redis(redis_config)

    if redis.is_connected:
        logger.info("Redis connected successfully")
        # Start event bus Redis subscriptions
        await eventbus.start_redis_subscription()
    else:
        logger.warning("Running without Redis - using in-memory fallback")

    if settings.webhook_fault_mode:
        webhook_outbox.set_fault_mode(settings.webhook_fault_mode, 1)

    outbox_task = asyncio.create_task(webhook_outbox.run_worker())

    yield

    # Shutdown
    logger.info("Shutting down FastAPI gateway...")
    webhook_outbox.stop()
    outbox_task.cancel()
    await replay.close()
    await close_redis()
    logger.info("Cleanup complete")


app = FastAPI(title="Secure Device Control - FastAPI Controller", lifespan=lifespan)
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
    """Health check endpoint with Redis status."""
    redis = get_redis_service()
    redis_ok = await redis.ping() if redis else False
    return {
        "status": "ok",
        "redis": "connected" if redis_ok else "disconnected",
    }


@app.websocket("/agent")
async def agent_ws(websocket: WebSocket):
    await websocket.accept()
    device_id = "unknown"
    session_id_assigned = None
    agent_info: dict[str, str] = {}
    agent_pubkey_b64: str | None = None
    try:
        try:
            raw = await websocket.receive_text()
        except WebSocketDisconnect as exc:
            logger.info("ws disconnected before AUTH: code=%s reason=%s", exc.code, exc.reason)
            return
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            logger.warning("AUTH_INVALID_PAYLOAD for device=%s", device_id)
            await websocket.send_json(build_auth_error(device_id, "AUTH_INVALID_PAYLOAD", "Invalid JSON"))
            await websocket.close(code=4400)
            return

        try:
            validate_auth_envelope(payload)
        except ValueError as exc:
            logger.warning("AUTH_INVALID_ENVELOPE for device=%s error=%s", device_id, str(exc))
            await websocket.send_json(build_auth_error(device_id, "AUTH_INVALID_ENVELOPE", str(exc)))
            await websocket.close(code=4400)
            return

        device_id = payload.get("device_id", device_id)

        # Load device public key for signature verification.
        agent_pubkey_b64 = device_registry.get_pubkey_b64(device_id)
        if not agent_pubkey_b64:
            # Fail-closed: do not authenticate, but allow the system to surface the device
            # as "pending_pairing" in Laravel for discovery UX.
            agent_info = payload.get("body", {}).get("agent_info", {}) or {}
            agent_info["connected_at"] = iso_timestamp()
            logger.warning("AUTH_UNKNOWN_DEVICE for device=%s", device_id)
            fire_and_forget(notify_device_online(device_id, "unpaired", agent_info))
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
        except ReplayError as exc:
            logger.warning("AUTH_REPLAY for device=%s error=%s", device_id, str(exc))
            await websocket.send_json(build_auth_error(device_id, "AUTH_REPLAY", str(exc)))
            await websocket.close(code=4401)
            return
        except SignatureError as exc:
            logger.warning("AUTH_INVALID_SIGNATURE for device=%s error=%s", device_id, str(exc))
            await websocket.send_json(build_auth_error(device_id, "AUTH_INVALID_SIGNATURE", str(exc)))
            await websocket.close(code=4401)
            return

        auth_token = payload["body"]["auth"]["jwt"]
        agent_info = payload["body"].get("agent_info", {})
        agent_info["connected_at"] = iso_timestamp()

        try:
            claims = await validate_auth_jwt(auth_token)
        except Exception as exc:
            logger.warning("AUTH_INVALID_JWT for device=%s error=%s", device_id, str(exc))
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
        current_policy = policy_resolver.current()
        fire_and_forget(
            notify_device_activated(
                device_id,
                session_id,
                iso_timestamp(),
                current_policy.get("policy_hash"),
            )
        )
        fire_and_forget(forward_attestation(device_id, iso_timestamp(), agent_info.get("attestation_hash")))

        auth_ack = build_auth_ack(device_id, session_id)
        await websocket.send_json(auth_ack)

        # Send latest policy/OTA and any queued commands
        await policy_resolver.send_current(websocket, device_id, session_id)
        await ota_manager.send_latest(websocket, device_id, session_id)
        for queued in await offline_queue.drain(device_id):
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
                except (ReplayError, SignatureError) as exc:
                    logger.warning(
                        "closing ws 4401 for device=%s reason=%s type=%s seq=%s",
                        device_id,
                        str(exc),
                        message.get("type"),
                        extract_seq_from_message(message),
                    )
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
                    body = message.get("body", {})
                    metrics = body.get("metrics", {})
                    policy_hash = body.get("policy_hash")
                    risk = risk_scorer.score(metrics)
                    fire_and_forget(
                        forward_telemetry_summary(
                            device_id,
                            metrics,
                            body.get("timestamp", message.get("timestamp", iso_timestamp())),
                            risk_score=risk,
                            policy_hash=policy_hash if isinstance(policy_hash, str) else None,
                            telemetry_scope=body.get("telemetry_scope"),
                            schema_version=body.get("schema_version", "v1"),
                            session_id=body.get("session_id", message.get("session_id")),
                            seq=body.get("seq", extract_seq_from_message(message)),
                            masked_fields=body.get("masked_fields"),
                            presence_state="online",
                            connection_mode="wss",
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
            except Exception as exc:
                logger.warning("ws message processing error for %s: %s", device_id, exc)
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
