from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

try:
    import redis.asyncio as redis

    HAVE_REDIS = True
except Exception:
    redis = None  # type: ignore
    HAVE_REDIS = False


class ReplayError(ValueError):
    pass


def _parse_iso8601(ts: str) -> datetime:
    # Supports trailing 'Z'
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    return datetime.fromisoformat(ts)


@dataclass(frozen=True)
class ReplayConfig:
    redis_url: Optional[str]
    max_clock_skew_seconds: int = 5
    require_seq: bool = True


class ReplayProtector:
    def __init__(self, cfg: ReplayConfig) -> None:
        self._cfg = cfg
        self._mem_last_seq: dict[str, int] = {}
        self._redis = None
        if cfg.redis_url and HAVE_REDIS and redis is not None:
            self._redis = redis.from_url(cfg.redis_url, decode_responses=True)

    async def close(self) -> None:
        if self._redis is not None:
            try:
                await self._redis.aclose()
            except Exception:
                pass

    def validate_timestamp(self, timestamp: str) -> None:
        try:
            dt = _parse_iso8601(timestamp)
        except Exception as exc:
            raise ReplayError("Invalid timestamp") from exc

        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)

        now = datetime.now(timezone.utc)
        skew = abs((now - dt).total_seconds())
        if skew > self._cfg.max_clock_skew_seconds:
            raise ReplayError(f"Timestamp skew too large ({skew:.2f}s)")

    async def check_and_update_seq(self, device_id: str, seq: Optional[int]) -> None:
        if seq is None:
            if self._cfg.require_seq:
                raise ReplayError("Missing seq")
            return

        if not isinstance(seq, int):
            raise ReplayError("seq must be integer")

        if seq <= 0:
            raise ReplayError("seq must be > 0")

        if self._redis is None:
            last = self._mem_last_seq.get(device_id, 0)
            if seq <= last:
                raise ReplayError("Replay detected (seq not increasing)")
            self._mem_last_seq[device_id] = seq
            return

        key = f"agent:last_seq:{device_id}"
        # Atomic compare-and-set via Lua
        script = (
            "local cur = redis.call('GET', KEYS[1]); "
            "if not cur then redis.call('SET', KEYS[1], ARGV[1]); return 1; end; "
            "cur = tonumber(cur); local nxt = tonumber(ARGV[1]); "
            "if nxt > cur then redis.call('SET', KEYS[1], ARGV[1]); return 1; end; "
            "return 0;"
        )
        ok = await self._redis.eval(script, 1, key, str(seq))
        if int(ok) != 1:
            raise ReplayError("Replay detected (seq not increasing)")

    async def check_and_store_nonce(self, device_id: str, nonce: str, ttl_seconds: int = 600) -> None:
        if not nonce:
            raise ReplayError("Missing nonce")

        if self._redis is None:
            # Best-effort in-memory nonce set with naive pruning
            # (sufficient for tests/dev, Redis required for production hardening)
            mem_key = f"{device_id}:{nonce}"
            if mem_key in self._mem_last_seq:  # type: ignore[operator]
                raise ReplayError("Replay detected (nonce reuse)")
            # reuse dict for small footprint
            self._mem_last_seq[mem_key] = 1  # type: ignore[index]
            return

        key = f"agent:nonce:{device_id}:{nonce}"
        created = await self._redis.set(key, "1", nx=True, ex=ttl_seconds)
        if not created:
            raise ReplayError("Replay detected (nonce reuse)")


def extract_seq_from_message(msg: dict) -> Optional[int]:
    # Prefer top-level seq if present, else body.seq.
    seq = msg.get("seq")
    if isinstance(seq, int):
        return seq
    body = msg.get("body") or {}
    if isinstance(body, dict) and isinstance(body.get("seq"), int):
        return body.get("seq")
    return None
