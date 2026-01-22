from __future__ import annotations

import json
import os
import random
import sqlite3
import threading
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta
from typing import Any, Dict, Iterable, List, Optional

import httpx

from app.config import settings
from app.services.fastapi_service_signing import ServiceSigningError, sign_fastapi_to_laravel
from app.ws.canonical import canonicalize_json


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _now_iso() -> str:
    return _now().isoformat().replace("+00:00", "Z")


def _parse_iso(ts: str) -> datetime:
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    return datetime.fromisoformat(ts)


@dataclass(frozen=True)
class OutboxConfig:
    db_path: str
    max_attempts: int = 6
    base_delay_seconds: int = 1
    max_delay_seconds: int = 60
    worker_interval_seconds: float = 1.0


class WebhookOutbox:
    """Durable webhook outbox with retry + DLQ semantics."""

    def __init__(self, cfg: OutboxConfig) -> None:
        self._cfg = cfg
        self._lock = threading.Lock()
        self._stop = False
        self._fault_mode: str = ""
        self._fault_remaining: int = 0
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        os.makedirs(os.path.dirname(self._cfg.db_path) or ".", exist_ok=True)
        conn = sqlite3.connect(self._cfg.db_path)
        conn.execute("PRAGMA journal_mode=WAL")
        return conn

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS webhook_outbox (
                    event_id TEXT PRIMARY KEY,
                    event_type TEXT NOT NULL,
                    destination_url TEXT NOT NULL,
                    payload_hash TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    next_retry_at TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending',
                    last_error TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """
            )

    def set_fault_mode(self, mode: str, count: int) -> None:
        """Enable a transient fault injection for webhook delivery."""
        self._fault_mode = mode.strip().lower()
        self._fault_remaining = max(0, int(count))

    def stop(self) -> None:
        self._stop = True

    def _compute_event_id(self, event_type: str, destination_url: str, payload: Dict[str, Any]) -> str:
        canonical = canonicalize_json(payload)
        seed = canonical + b"|" + event_type.encode("utf-8") + b"|" + destination_url.encode("utf-8")
        return hashlib_sha256(seed)

    def _serialize_payload(self, payload: Dict[str, Any]) -> str:
        canonical = canonicalize_json(payload)
        return canonical.decode("utf-8")

    def _payload_hash(self, payload: Dict[str, Any]) -> str:
        return hashlib_sha256(canonicalize_json(payload))

    async def enqueue_and_send(self, event_type: str, destination_url: str, payload: Dict[str, Any]) -> str:
        event_id = payload.get("event_id")
        if not isinstance(event_id, str) or not event_id:
            event_id = self._compute_event_id(event_type, destination_url, payload)
            payload["event_id"] = event_id

        payload_json = self._serialize_payload(payload)
        payload_hash = self._payload_hash(payload)
        now_iso = _now_iso()

        with self._lock:
            with self._connect() as conn:
                conn.execute(
                    """
                    INSERT OR IGNORE INTO webhook_outbox
                        (event_id, event_type, destination_url, payload_hash, payload_json,
                         attempts, next_retry_at, status, last_error, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, 0, ?, 'pending', NULL, ?, ?)
                    """,
                    (event_id, event_type, destination_url, payload_hash, payload_json, now_iso, now_iso, now_iso),
                )

        delivered, error = await self._deliver(destination_url, payload)
        if delivered:
            self._mark_delivered(event_id)
        else:
            self._mark_retry(event_id, error)

        return event_id

    async def run_worker(self) -> None:
        while not self._stop:
            due = self._fetch_due(limit=50)
            if not due:
                await asyncio_sleep(self._cfg.worker_interval_seconds)
                continue

            for row in due:
                event_id = row["event_id"]
                payload = json.loads(row["payload_json"])
                delivered, error = await self._deliver(row["destination_url"], payload)
                if delivered:
                    self._mark_delivered(event_id)
                else:
                    self._mark_retry(event_id, error, attempts=row["attempts"])

    def _fetch_due(self, limit: int = 100) -> List[Dict[str, Any]]:
        now_iso = _now_iso()
        with self._lock:
            with self._connect() as conn:
                rows = conn.execute(
                    """
                    SELECT event_id, event_type, destination_url, payload_json, attempts, next_retry_at
                    FROM webhook_outbox
                    WHERE status = 'pending' AND next_retry_at <= ?
                    ORDER BY next_retry_at ASC
                    LIMIT ?
                    """,
                    (now_iso, limit),
                ).fetchall()
        return [
            {
                "event_id": r[0],
                "event_type": r[1],
                "destination_url": r[2],
                "payload_json": r[3],
                "attempts": int(r[4]),
                "next_retry_at": r[5],
            }
            for r in rows
        ]

    async def _deliver(self, destination_url: str, payload: Dict[str, Any]) -> tuple[bool, Optional[str]]:
        if self._fault_mode == "timeout" and self._fault_remaining > 0:
            self._fault_remaining -= 1
            return False, "fault_injected_timeout"

        headers = None
        try:
            headers = sign_fastapi_to_laravel(payload)
        except ServiceSigningError as exc:
            if settings.sign_laravel_webhooks:
                return False, str(exc)
            headers = None

        if headers is None:
            headers = {}
        headers.setdefault("X-Event-Id", payload.get("event_id", ""))

        try:
            async with httpx.AsyncClient() as client:
                resp = await client.post(destination_url, json=payload, headers=headers, timeout=5.0)
            if resp.status_code >= 200 and resp.status_code < 300:
                return True, None
            return False, f"http_{resp.status_code}"
        except Exception as exc:
            return False, str(exc)

    def _mark_delivered(self, event_id: str) -> None:
        now_iso = _now_iso()
        with self._lock:
            with self._connect() as conn:
                conn.execute(
                    """
                    UPDATE webhook_outbox
                    SET status = 'delivered', updated_at = ?, last_error = NULL
                    WHERE event_id = ?
                    """,
                    (now_iso, event_id),
                )

    def _mark_retry(self, event_id: str, error: Optional[str], attempts: Optional[int] = None) -> None:
        now = _now()
        now_iso = now.isoformat().replace("+00:00", "Z")
        if attempts is None:
            attempts = self._get_attempts(event_id)
        next_attempts = attempts + 1
        if next_attempts >= self._cfg.max_attempts:
            self._mark_dlq(event_id, error)
            return

        delay = min(self._cfg.base_delay_seconds * (2 ** attempts), self._cfg.max_delay_seconds)
        jitter = random.uniform(0.8, 1.2)
        next_retry_at = (now + timedelta(seconds=delay * jitter)).isoformat().replace("+00:00", "Z")

        with self._lock:
            with self._connect() as conn:
                conn.execute(
                    """
                    UPDATE webhook_outbox
                    SET attempts = ?, next_retry_at = ?, status = 'pending', last_error = ?, updated_at = ?
                    WHERE event_id = ?
                    """,
                    (next_attempts, next_retry_at, error, now_iso, event_id),
                )

    def _mark_dlq(self, event_id: str, error: Optional[str]) -> None:
        now_iso = _now_iso()
        with self._lock:
            with self._connect() as conn:
                conn.execute(
                    """
                    UPDATE webhook_outbox
                    SET status = 'dlq', last_error = ?, updated_at = ?
                    WHERE event_id = ?
                    """,
                    (error, now_iso, event_id),
                )

    def _get_attempts(self, event_id: str) -> int:
        with self._lock:
            with self._connect() as conn:
                row = conn.execute(
                    "SELECT attempts FROM webhook_outbox WHERE event_id = ?",
                    (event_id,),
                ).fetchone()
        if not row:
            return 0
        return int(row[0])


def hashlib_sha256(payload: bytes) -> str:
    import hashlib

    return hashlib.sha256(payload).hexdigest()


async def asyncio_sleep(seconds: float) -> None:
    import asyncio

    await asyncio.sleep(seconds)
