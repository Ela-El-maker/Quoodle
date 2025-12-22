from __future__ import annotations

import json
import os
import sqlite3
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class DeviceKeyRegistryConfig:
    db_path: str
    seed_json_path: Optional[str] = None


class DeviceKeyRegistry:
    """Maps device_id -> Ed25519 public key (base64).

    Minimal implementation using SQLite (built-in) to satisfy "database table" requirement.
    Seed data can optionally be loaded from a JSON file:
      {"PC001": "<PUBKEY_B64>", ...}
    """

    def __init__(self, cfg: DeviceKeyRegistryConfig) -> None:
        self._db_path = cfg.db_path
        self._seed_json_path = cfg.seed_json_path
        self._ensure_schema()
        if self._seed_json_path:
            self._seed_from_json(self._seed_json_path)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self._db_path)
        conn.execute("PRAGMA journal_mode=WAL")
        return conn

    def _ensure_schema(self) -> None:
        os.makedirs(os.path.dirname(self._db_path) or ".", exist_ok=True)
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS device_keys (
                    device_id TEXT PRIMARY KEY,
                    ed25519_pub_b64 TEXT NOT NULL,
                    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
                );
                """
            )

    def _seed_from_json(self, path: str) -> None:
        if not os.path.exists(path):
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            return

        if not isinstance(data, dict):
            return

        with self._connect() as conn:
            for device_id, pub_b64 in data.items():
                if not isinstance(device_id, str) or not isinstance(pub_b64, str) or not pub_b64:
                    continue
                conn.execute(
                    "INSERT OR REPLACE INTO device_keys(device_id, ed25519_pub_b64, updated_at) VALUES (?, ?, datetime('now'))",
                    (device_id, pub_b64.strip()),
                )

    def get_pubkey_b64(self, device_id: str) -> Optional[str]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT ed25519_pub_b64 FROM device_keys WHERE device_id = ?", (device_id,)
            ).fetchone()
        if not row:
            return None
        return str(row[0])

    def upsert_pubkey_b64(self, device_id: str, pubkey_b64: str) -> None:
        with self._connect() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO device_keys(device_id, ed25519_pub_b64, updated_at) VALUES (?, ?, datetime('now'))",
                (device_id, pubkey_b64.strip()),
            )
