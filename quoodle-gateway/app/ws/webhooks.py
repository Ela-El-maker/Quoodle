import asyncio
from typing import Any, Dict

from app.config import settings
from app.state import webhook_outbox


async def _post(path: str, payload: Dict[str, Any], event_type: str) -> None:
    url = f"{settings.laravel_webhook_base.rstrip('/')}/{path.lstrip('/')}"
    await webhook_outbox.enqueue_and_send(event_type, url, payload)


async def notify_device_online(device_id: str, session_id: str, agent_info: Dict[str, Any]) -> None:
    payload = {
        "device_id": device_id,
        "session_id": session_id,
        "agent_version": agent_info.get("agent_version"),
        "os_build": agent_info.get("os_build"),
        "attestation_hash": agent_info.get("attestation_hash"),
        "connected_at": agent_info.get("connected_at"),
    }
    await _post("device/online", payload, "device_online")


async def notify_device_activated(device_id: str, session_id: str, activated_at: str, policy_hash: str | None) -> None:
    payload = {
        "device_id": device_id,
        "session_id": session_id,
        "activated_at": activated_at,
        "policy_hash": policy_hash,
    }
    await _post("device/activated", payload, "device_activated")


async def notify_device_offline(device_id: str, session_id: str | None, last_seen: str, reason: str) -> None:
    payload = {
        "device_id": device_id,
        "session_id": session_id,
        "last_seen": last_seen,
        "reason": reason,
    }
    await _post("device/offline", payload, "device_offline")


async def forward_command_ack(body: Dict[str, Any], device_id: str, timestamp: str) -> None:
    payload = {
        "command_id": body.get("command_message_id"),
        "device_id": device_id,
        "status": body.get("status"),
        "reason": body.get("reason"),
        "timestamp": timestamp,
    }
    await _post("command/ack", payload, "command_ack")


async def forward_telemetry_summary(
    device_id: str,
    metrics: Dict[str, Any],
    timestamp: str,
    risk_score: float | None = None,
    policy_hash: str | None = None,
) -> None:
    try:
        kernel_event = metrics.get("kernel_event") if isinstance(metrics, dict) else None
        def _percent(val: str | None) -> float | None:
            if not val:
                return None
            stripped = val.replace("%", "")
            try:
                return float(stripped)
            except ValueError:
                return None

        rollup = {
            "avg_cpu": _percent(metrics.get("cpu")) or 0.0,
            "avg_ram": _percent(metrics.get("ram")) or 0.0,
            "avg_disk": _percent(metrics.get("disk_usage")) or 0.0,
            "max_cpu": _percent(metrics.get("cpu")) or 0.0,
            "risk_score_avg": risk_score or 0.0,
            "policy_hash": policy_hash,
        }
        if kernel_event:
            rollup["kernel_event"] = kernel_event
    except Exception:
        rollup = {
            "avg_cpu": 0.0,
            "avg_ram": 0.0,
            "avg_disk": 0.0,
            "max_cpu": 0.0,
            "risk_score_avg": 0.0,
            "policy_hash": policy_hash,
        }
        if isinstance(metrics, dict) and metrics.get("kernel_event"):
            rollup["kernel_event"] = metrics.get("kernel_event")

    payload = {
        "device_id": device_id,
        "timestamp": timestamp,
        "rollup": rollup,
    }
    await _post("telemetry/summary", payload, "telemetry_summary")


async def forward_attestation(device_id: str, timestamp: str, attestation_hash: str | None) -> None:
    payload = {
        "device_id": device_id,
        "timestamp": timestamp,
        "attestation": {
            "agent_hash": attestation_hash,
            "kernelservice_hash": None,
            "tpm_quote": None,
            "status": "pass" if attestation_hash else "unknown",
        },
    }
    await _post("security/attestation", payload, "security_attestation")


def fire_and_forget(coro: asyncio.Future) -> None:
    asyncio.create_task(coro)
