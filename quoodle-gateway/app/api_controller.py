import uuid
from typing import Any, Dict, Iterable
import logging

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, ValidationError

from app.api.schemas import (
    CommandDispatchRequest,
    DevicePairedRequest,
    PolicyPushRequest,
    OTAPublishRequest,
    QuarantineRequest,
    TelemetryHeartbeatRequest,
    TelemetryBatchRequest,
)
from app.config import settings
from app.state import (
    event_bus,
    offline_queue,
    ota_manager,
    policy_resolver,
    quarantine_handler,
    risk_scorer,
    webhook_outbox,
)
from app.ws.webhooks import fire_and_forget, forward_telemetry_summary
from app.ws.connection_manager import ConnectionManager
from app.ws.protocol import iso_timestamp, compute_sig, get_signing_public_key_b64, validate_kernel_event_metrics
from app.ws.auth import validate_auth_jwt

logger = logging.getLogger("quoodle.api.telemetry")

RUNTIME_SUPPORTED_METHODS = {
    "ping",
    "lock_screen",
    "reboot_device",
    "shutdown_device",
    "collect_system_info",
    "screenshot",
    "list_processes",
    "list_services",
    "list_connections",
    "list_mounts",
    "network_info",
    "get_active_window",
    "list_files",
    "download_file",
    "create_directory",
    "create_file",
    "delete_file",
    "delete_directory",
}

TELEMETRY_ALLOWLIST_COMMON = {
    "cpu",
    "ram",
    "disk_usage",
    "network_tx",
    "network_rx",
    "risk_score",
    "battery_pct",
    "os_version",
    "os_build",
    "agent_version",
    "patch_level",
    "policy_in_sync",
    "compliance_status",
    "geo_hash",
}
TELEMETRY_ALLOWLIST_KERNEL = {"kernel_event"}
TELEMETRY_COUNTERS = {
    "accepted": 0,
    "rejected": 0,
    "partial_accept": 0,
    "kernel_accepted": 0,
    "kernel_rejected": 0,
    "kernel_partial_accept": 0,
    "auth_fail": 0,
    "schema_fail": 0,
}


class DeviceKeyUpsertRequest(BaseModel):
    ed25519_pubkey_b64: str


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
            "policy_version": meta.get(
                "policy_version", payload.get("policy", {}).get("policy_version", settings.policy_version)
            ),
            "policy_hash": payload.get("policy", {}).get("policy_hash"),
            "compliance": payload.get("compliance"),
        },
        "message_id": command_message_id,
        "trace_id": trace_id,
        "seq": payload.get("seq", 1),
        "sig": envelope.get("sig"),
    }
    # Always re-sign the command envelope with the gateway's WSS signing key.
    command_envelope["sig"] = compute_sig(command_envelope)

    message = {
        "type": "COMMAND_DELIVERY",
        "from": settings.controller_id,
        "device_id": device_id,
        "message_id": f"m-cmd-delivery-{uuid.uuid4()}",
        "session_id": session_id,
        "timestamp": iso_timestamp(),
        "body": {"command_envelope": command_envelope},
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


def _filter_metrics(metrics: Dict[str, Any], scope: str) -> tuple[Dict[str, Any], list[str]]:
    allowed: Iterable[str] = TELEMETRY_ALLOWLIST_COMMON
    if scope == "kernel_event":
        allowed = TELEMETRY_ALLOWLIST_KERNEL

    filtered: Dict[str, Any] = {}
    masked: list[str] = []
    for key, value in metrics.items():
        if key in allowed:
            filtered[key] = value
        else:
            masked.append(key)
    return filtered, masked


def _parse_percent_or_number(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        candidate = value.strip().replace("%", "")
        try:
            return float(candidate)
        except ValueError:
            return None
    return None


def _build_rollup(
    metrics: Dict[str, Any],
    policy_hash: str | None,
    risk_score: float | None,
    scope: str,
    connection_mode: str = "http_heartbeat",
) -> Dict[str, Any]:
    rollup: Dict[str, Any] = {
        "avg_cpu": _parse_percent_or_number(metrics.get("cpu")),
        "avg_ram": _parse_percent_or_number(metrics.get("ram")),
        "avg_disk": _parse_percent_or_number(metrics.get("disk_usage")),
        "avg_tx": _parse_percent_or_number(metrics.get("network_tx")),
        "avg_rx": _parse_percent_or_number(metrics.get("network_rx")),
        "max_cpu": _parse_percent_or_number(metrics.get("cpu")),
        "risk_score_avg": risk_score,
        "policy_hash": policy_hash,
        "presence_state": "online",
        "connection_mode": connection_mode,
    }
    if scope == "kernel_event" and isinstance(metrics.get("kernel_event"), dict):
        rollup["kernel_event"] = metrics.get("kernel_event")
    return rollup


def _inc_counter(name: str) -> None:
    TELEMETRY_COUNTERS[name] = TELEMETRY_COUNTERS.get(name, 0) + 1


def _inc_scope_counter(scope: str, status: str) -> None:
    if scope != "kernel_event":
        return
    if status == "accepted":
        _inc_counter("kernel_accepted")
    elif status == "partial_accept":
        _inc_counter("kernel_partial_accept")
    elif status == "rejected":
        _inc_counter("kernel_rejected")


def _validate_kernel_entry(metrics: Dict[str, Any], telemetry_scope: str) -> str | None:
    if telemetry_scope != "kernel_event":
        return None
    try:
        validate_kernel_event_metrics(metrics)
        return None
    except ValueError as exc:
        return str(exc)


async def _require_telemetry_bearer(request: Request, expected_device_id: str) -> Dict[str, Any]:
    auth_header = request.headers.get("authorization", "").strip()
    if not auth_header or not auth_header.lower().startswith("bearer "):
        _inc_counter("auth_fail")
        raise HTTPException(status_code=401, detail={"reason": "auth_missing_bearer"})

    token = auth_header[7:].strip()
    if not token:
        _inc_counter("auth_fail")
        raise HTTPException(status_code=401, detail={"reason": "auth_missing_token"})

    try:
        claims = await validate_auth_jwt(token)
    except Exception:
        _inc_counter("auth_fail")
        raise HTTPException(status_code=401, detail={"reason": "auth_invalid_token"})

    if claims.get("scope") != "agent":
        _inc_counter("auth_fail")
        raise HTTPException(status_code=403, detail={"reason": "auth_invalid_scope"})

    subject = str(claims.get("sub") or "")
    if subject and subject != expected_device_id:
        _inc_counter("auth_fail")
        raise HTTPException(status_code=403, detail={"reason": "auth_device_mismatch"})

    return claims


async def _require_agent_bearer(request: Request) -> tuple[str, Dict[str, Any]]:
    auth_header = request.headers.get("authorization", "").strip()
    if not auth_header or not auth_header.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail={"reason": "auth_missing_bearer"})

    token = auth_header[7:].strip()
    if not token:
        raise HTTPException(status_code=401, detail={"reason": "auth_missing_token"})

    try:
        claims = await validate_auth_jwt(token)
    except Exception:
        raise HTTPException(status_code=401, detail={"reason": "auth_invalid_token"})

    if claims.get("scope") != "agent":
        raise HTTPException(status_code=403, detail={"reason": "auth_invalid_scope"})

    return token, claims


def _control_plane_artifact_url(path: str) -> str:
    base = settings.control_plane_api_base.rstrip("/")
    suffix = path if path.startswith("/") else f"/{path}"
    return f"{base}{suffix}"


def _gateway_upload_url(request: Request) -> str:
    base = str(request.base_url).rstrip("/")
    return f"{base}/api/v1/agent/artifact/upload"


def create_router(manager: ConnectionManager) -> APIRouter:
    router = APIRouter(prefix="/api/v1")

    @router.get("/controller/signing-key")
    async def controller_signing_key():
        pubkey = get_signing_public_key_b64()
        if not pubkey:
            raise HTTPException(status_code=503, detail={"reason": "signing_key_unavailable"})
        return {
            "controller_id": settings.controller_id,
            "controller_pubkey_b64": pubkey,
        }

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

    @router.post("/telemetry/heartbeat")
    async def telemetry_heartbeat(payload_raw: Dict[str, Any], request: Request):
        try:
            payload = TelemetryHeartbeatRequest.model_validate(payload_raw)
        except ValidationError as exc:
            _inc_counter("schema_fail")
            raise HTTPException(status_code=422, detail={"reason": "invalid_schema", "errors": exc.errors()})

        await _require_telemetry_bearer(request, payload.device_id)
        kernel_reason = _validate_kernel_entry(payload.metrics, payload.telemetry_scope)
        if kernel_reason is not None:
            _inc_counter("rejected")
            _inc_scope_counter(payload.telemetry_scope, "rejected")
            raise HTTPException(status_code=422, detail={"reason": kernel_reason})
        filtered_metrics, dropped = _filter_metrics(payload.metrics, payload.telemetry_scope)
        risk = risk_scorer.score(filtered_metrics)
        rollup = _build_rollup(filtered_metrics, payload.policy_hash, risk, payload.telemetry_scope, "http_heartbeat")

        await event_bus.emit_telemetry(
            payload.device_id,
            {
                "schema_version": payload.schema_version,
                "session_id": payload.session_id,
                "timestamp": payload.timestamp,
                "seq": payload.seq,
                "telemetry_scope": payload.telemetry_scope,
                "metrics": filtered_metrics,
                "masked_fields": sorted(set((payload.masked_fields or []) + dropped)),
            },
        )

        fire_and_forget(
            forward_telemetry_summary(
                payload.device_id,
                filtered_metrics,
                payload.timestamp,
                risk_score=risk,
                policy_hash=payload.policy_hash,
                telemetry_scope=payload.telemetry_scope,
                schema_version=payload.schema_version,
                session_id=payload.session_id,
                seq=payload.seq,
                masked_fields=sorted(set((payload.masked_fields or []) + dropped)),
                presence_state="online",
                connection_mode="http_heartbeat",
            )
        )

        _inc_counter("accepted")
        _inc_scope_counter(payload.telemetry_scope, "accepted")
        logger.debug("telemetry heartbeat accepted device=%s scope=%s seq=%s", payload.device_id, payload.telemetry_scope, payload.seq)
        return {
            "status": "accepted",
            "device_id": payload.device_id,
            "timestamp": payload.timestamp,
            "telemetry_scope": payload.telemetry_scope,
            "masked_fields": sorted(set((payload.masked_fields or []) + dropped)),
            "rollup": rollup,
            "counters": TELEMETRY_COUNTERS,
        }

    @router.post("/telemetry/batch")
    async def telemetry_batch(payload_raw: Dict[str, Any], request: Request):
        try:
            payload = TelemetryBatchRequest.model_validate(payload_raw)
        except ValidationError as exc:
            _inc_counter("schema_fail")
            raise HTTPException(status_code=422, detail={"reason": "invalid_schema", "errors": exc.errors()})

        await _require_telemetry_bearer(request, payload.device_id)
        accepted = 0
        rejected = 0
        accepted_kernel = 0
        rejected_kernel = 0
        errors: list[dict[str, Any]] = []
        latest_rollup: Dict[str, Any] | None = None

        for index, entry in enumerate(payload.entries):
            if entry.device_id != payload.device_id:
                rejected += 1
                if entry.telemetry_scope == "kernel_event":
                    rejected_kernel += 1
                errors.append({"index": index, "reason": "device_id_mismatch"})
                continue
            kernel_reason = _validate_kernel_entry(entry.metrics, entry.telemetry_scope)
            if kernel_reason is not None:
                rejected += 1
                if entry.telemetry_scope == "kernel_event":
                    rejected_kernel += 1
                errors.append({"index": index, "reason": kernel_reason})
                continue

            filtered_metrics, dropped = _filter_metrics(entry.metrics, entry.telemetry_scope)
            risk = risk_scorer.score(filtered_metrics)
            latest_rollup = _build_rollup(filtered_metrics, entry.policy_hash, risk, entry.telemetry_scope, "http_heartbeat")

            await event_bus.emit_telemetry(
                entry.device_id,
                {
                    "schema_version": entry.schema_version,
                    "session_id": entry.session_id,
                    "timestamp": entry.timestamp,
                    "seq": entry.seq,
                    "telemetry_scope": entry.telemetry_scope,
                    "metrics": filtered_metrics,
                    "masked_fields": sorted(set((entry.masked_fields or []) + dropped)),
                },
            )
            fire_and_forget(
                forward_telemetry_summary(
                    entry.device_id,
                    filtered_metrics,
                    entry.timestamp,
                    risk_score=risk,
                    policy_hash=entry.policy_hash,
                    telemetry_scope=entry.telemetry_scope,
                    schema_version=entry.schema_version,
                    session_id=entry.session_id,
                    seq=entry.seq,
                    masked_fields=sorted(set((entry.masked_fields or []) + dropped)),
                    presence_state="online",
                    connection_mode="http_heartbeat",
                )
            )
            accepted += 1
            if entry.telemetry_scope == "kernel_event":
                accepted_kernel += 1

        status = "accepted" if rejected == 0 else ("partial_accept" if accepted > 0 else "rejected")
        _inc_counter(status)
        if accepted_kernel > 0 or rejected_kernel > 0:
            kernel_status = "accepted" if rejected_kernel == 0 else ("partial_accept" if accepted_kernel > 0 else "rejected")
            _inc_scope_counter("kernel_event", kernel_status)
        logger.debug(
            "telemetry batch processed device=%s accepted=%s rejected=%s kernel_accepted=%s kernel_rejected=%s status=%s",
            payload.device_id,
            accepted,
            rejected,
            accepted_kernel,
            rejected_kernel,
            status,
        )
        return {
            "status": status,
            "device_id": payload.device_id,
            "accepted": accepted,
            "rejected": rejected,
            "errors": errors,
            "latest_rollup": latest_rollup,
            "counters": TELEMETRY_COUNTERS,
        }

    @router.post("/agent/artifact/request")
    async def agent_artifact_request(request: Request):
        token, _claims = await _require_agent_bearer(request)
        raw_body = await request.body()

        headers = {"Authorization": f"Bearer {token}"}
        content_type = request.headers.get("content-type")
        if content_type:
            headers["Content-Type"] = content_type

        try:
            async with httpx.AsyncClient() as client:
                upstream = await client.post(
                    _control_plane_artifact_url("/api/artifact/request"),
                    content=raw_body,
                    headers=headers,
                    timeout=20.0,
                )
        except httpx.HTTPError:
            raise HTTPException(status_code=502, detail={"reason": "artifact_request_upstream_unreachable"})

        try:
            payload = upstream.json()
        except ValueError:
            return Response(
                content=upstream.content,
                status_code=upstream.status_code,
                media_type=upstream.headers.get("content-type"),
            )

        if (
            isinstance(payload, dict)
            and upstream.status_code >= 200
            and upstream.status_code < 300
            and payload.get("status") == "ok"
        ):
            payload["upload_url"] = _gateway_upload_url(request)

        return JSONResponse(payload, status_code=upstream.status_code)

    @router.post("/agent/artifact/upload")
    async def agent_artifact_upload(request: Request):
        token, _claims = await _require_agent_bearer(request)
        raw_body = await request.body()

        headers = {"Authorization": f"Bearer {token}"}
        content_type = request.headers.get("content-type")
        if content_type:
            headers["Content-Type"] = content_type

        try:
            async with httpx.AsyncClient() as client:
                upstream = await client.post(
                    _control_plane_artifact_url("/api/artifact/upload"),
                    content=raw_body,
                    headers=headers,
                    timeout=90.0,
                )
        except httpx.HTTPError:
            raise HTTPException(status_code=502, detail={"reason": "artifact_upload_upstream_unreachable"})

        try:
            payload = upstream.json()
            return JSONResponse(payload, status_code=upstream.status_code)
        except ValueError:
            return Response(
                content=upstream.content,
                status_code=upstream.status_code,
                media_type=upstream.headers.get("content-type"),
            )

    @router.post("/command/dispatch")
    async def dispatch_command(payload: CommandDispatchRequest):
        device_id = payload.device_id
        if payload.method not in RUNTIME_SUPPORTED_METHODS:
            return build_dispatch_response("blocked", device_id, payload.command_id, "not_supported_runtime")

        if quarantine_handler.is_blocked(device_id, payload.method):
            return build_dispatch_response("blocked", device_id, payload.command_id, "device_quarantined")

        entry = await manager.get(device_id)
        if not entry:
            await offline_queue.enqueue(device_id, payload.model_dump())
            return build_dispatch_response("queued_offline", device_id, payload.command_id, "device not connected")

        message = build_command_delivery(payload.model_dump(), entry.session_id)
        await entry.websocket.send_json(message)
        await event_bus.publish("commands.dispatched.v1", {"command_id": payload.command_id, "device_id": device_id})
        return build_dispatch_response("dispatched", device_id, payload.command_id, None)

    @router.post("/policy/push")
    async def push_policy(payload: PolicyPushRequest):
        app_lock_bundle = payload.app_lock.model_dump() if payload.app_lock is not None else None
        target_device_ids = payload.target_device_ids or []
        target_device_set = set(target_device_ids)
        current = policy_resolver.update(
            policy_version=payload.policy_version,
            policy_hash=payload.policy_hash,
            policy_url=payload.policy_url,
            signed_at=payload.signed_at,
            signature=payload.signature,
            app_lock=app_lock_bundle,
            target_device_ids=target_device_ids,
        )

        entries = await manager.all_entries()
        if target_device_set:
            entries = [entry for entry in entries if entry.device_id in target_device_set]

        for entry in entries:
            policy_msg = policy_resolver.build_message(entry.device_id, entry.session_id)
            await entry.websocket.send_json(policy_msg)

        await event_bus.publish("policy.updated.v1", current)
        return {
            "status": "accepted",
            "reason": None,
            "policy": current,
            "target_device_ids": target_device_ids,
            "delivered_count": len(entries),
        }

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

    @router.post("/test/fault")
    async def set_fault(payload: Dict[str, Any]):
        if not settings.enable_test_endpoints:
            raise HTTPException(status_code=404, detail="not_found")
        mode = str(payload.get("mode", "")).strip().lower()
        count = int(payload.get("count", 1))
        webhook_outbox.set_fault_mode(mode, count)
        return {"status": "ok", "mode": mode, "count": count}

    @router.post("/webhook/device/paired")
    async def device_paired(payload: DevicePairedRequest):
        # Lazily import to avoid circular references with app.main.
        from app.main import device_registry

        device_registry.upsert_pubkey_b64(payload.device_id, payload.ed25519_pubkey_b64)
        await event_bus.publish("device.paired.v1", payload.model_dump())
        return {"status": "ack", "device_id": payload.device_id}

    @router.post("/admin/quarantine/{device_id}")
    async def set_quarantine(device_id: str, payload: QuarantineRequest):
        quarantine_handler.set_quarantine(device_id, payload.reason)
        return {
            "status": "quarantined",
            "device_id": device_id,
            "reason": payload.reason,
            "allowlist": quarantine_handler.allowlist(),
        }

    @router.post("/admin/device-keys/{device_id}")
    async def upsert_device_key(device_id: str, payload: DeviceKeyUpsertRequest):
        # Lazily import to avoid circular references with app.main.
        from app.main import device_registry

        pub = payload.ed25519_pubkey_b64.strip()
        if not pub:
            raise HTTPException(status_code=400, detail="ed25519_pubkey_b64 required")

        device_registry.upsert_pubkey_b64(device_id, pub)
        return {"status": "ok", "device_id": device_id}

    @router.delete("/admin/quarantine/{device_id}")
    async def lift_quarantine(device_id: str):
        quarantine_handler.lift_quarantine(device_id)
        return {"status": "cleared", "device_id": device_id}

    return router
