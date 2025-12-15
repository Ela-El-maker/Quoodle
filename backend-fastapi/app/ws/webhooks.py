import asyncio
from typing import Any, Dict

import httpx

from app.config import settings


async def _post(path: str, payload: Dict[str, Any]) -> None:
    url = f"{settings.laravel_webhook_base.rstrip('/')}/{path.lstrip('/')}"
    async with httpx.AsyncClient() as client:
        await client.post(url, json=payload, timeout=5.0)


async def notify_device_online(device_id: str, session_id: str, agent_info: Dict[str, Any]) -> None:
    payload = {
        "device_id": device_id,
        "session_id": session_id,
        "agent_version": agent_info.get("agent_version"),
        "os_build": agent_info.get("os_build"),
        "attestation_hash": agent_info.get("attestation_hash"),
        "connected_at": agent_info.get("connected_at"),
    }
    await _post("device/online", payload)


async def notify_device_offline(device_id: str, session_id: str | None, last_seen: str, reason: str) -> None:
    payload = {
        "device_id": device_id,
        "session_id": session_id,
        "last_seen": last_seen,
        "reason": reason,
    }
    await _post("device/offline", payload)


async def forward_command_ack(body: Dict[str, Any], device_id: str, timestamp: str) -> None:
    payload = {
        "command_id": body.get("command_message_id"),
        "device_id": device_id,
        "status": body.get("status"),
        "reason": body.get("reason"),
        "timestamp": timestamp,
    }
    await _post("command/ack", payload)


async def forward_telemetry_summary(device_id: str, metrics: Dict[str, Any], timestamp: str, risk_score: float | None = None) -> None:
    try:
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
        }
    except Exception:
        rollup = {
            "avg_cpu": 0.0,
            "avg_ram": 0.0,
            "avg_disk": 0.0,
            "max_cpu": 0.0,
            "risk_score_avg": 0.0,
        }

    payload = {
        "device_id": device_id,
        "timestamp": timestamp,
        "rollup": rollup,
    }
    await _post("telemetry/summary", payload)


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
    await _post("security/attestation", payload)


def fire_and_forget(coro: asyncio.Future) -> None:
    asyncio.create_task(coro)
