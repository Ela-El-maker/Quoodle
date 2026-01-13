"""
Device presence tracking with Redis-backed distributed storage.

Tracks which devices are online across multiple FastAPI instances.
Falls back to in-memory storage when Redis is unavailable.
"""

from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass
from typing import Optional

from app.services.redis_service import RedisService, get_redis_service

logger = logging.getLogger(__name__)


@dataclass
class PresenceInfo:
    """Information about a device's presence."""

    device_id: str
    session_id: str
    connected_at: float
    last_heartbeat: float
    agent_version: Optional[str] = None
    ip_address: Optional[str] = None


class PresenceTracker:
    """
    Track device presence with Redis for distributed deployment.

    Features:
    - Distributed presence across multiple gateway instances
    - Heartbeat tracking with TTL
    - Session metadata storage
    - Pub/Sub notifications for presence changes
    """

    # Redis keys
    KEY_ONLINE_SET = "presence:online"
    KEY_SESSION_PREFIX = "presence:session:"
    KEY_HEARTBEAT_PREFIX = "presence:hb:"
    CHANNEL_PRESENCE = "presence:events"

    # TTL for presence data (seconds)
    HEARTBEAT_TTL = 120  # Device considered offline if no heartbeat for 2 minutes
    SESSION_TTL = 86400  # Session info kept for 24 hours

    def __init__(self, redis: Optional[RedisService] = None) -> None:
        self._redis = redis
        self._local_online: set[str] = set()  # Fallback
        self._local_sessions: dict[str, PresenceInfo] = {}

    @property
    def redis(self) -> RedisService:
        """Get Redis service, using global instance if not injected."""
        if self._redis is None:
            self._redis = get_redis_service()
        return self._redis

    async def online(
        self,
        device_id: str,
        session_id: str = "",
        agent_version: Optional[str] = None,
        ip_address: Optional[str] = None,
    ) -> None:
        """Mark a device as online."""
        now = time.time()
        info = PresenceInfo(
            device_id=device_id,
            session_id=session_id,
            connected_at=now,
            last_heartbeat=now,
            agent_version=agent_version,
            ip_address=ip_address,
        )

        # Add to online set
        await self.redis.sadd(self.KEY_ONLINE_SET, device_id)

        # Store session info
        session_data = json.dumps(
            {
                "session_id": info.session_id,
                "connected_at": info.connected_at,
                "last_heartbeat": info.last_heartbeat,
                "agent_version": info.agent_version,
                "ip_address": info.ip_address,
            }
        )
        await self.redis.set(
            f"{self.KEY_SESSION_PREFIX}{device_id}",
            session_data,
            ex=self.SESSION_TTL,
        )

        # Set heartbeat with TTL
        await self.redis.set(
            f"{self.KEY_HEARTBEAT_PREFIX}{device_id}",
            str(now),
            ex=self.HEARTBEAT_TTL,
        )

        # Publish presence event
        await self.redis.publish(
            self.CHANNEL_PRESENCE,
            json.dumps({"event": "online", "device_id": device_id, "session_id": session_id}),
        )

        # Local fallback
        self._local_online.add(device_id)
        self._local_sessions[device_id] = info

        logger.info("Device online: %s (session: %s)", device_id, session_id)

    async def offline(self, device_id: str) -> None:
        """Mark a device as offline."""
        # Remove from online set
        await self.redis.srem(self.KEY_ONLINE_SET, device_id)

        # Delete heartbeat key (session info kept for history)
        await self.redis.delete(f"{self.KEY_HEARTBEAT_PREFIX}{device_id}")

        # Publish presence event
        await self.redis.publish(
            self.CHANNEL_PRESENCE,
            json.dumps({"event": "offline", "device_id": device_id}),
        )

        # Local fallback
        self._local_online.discard(device_id)

        logger.info("Device offline: %s", device_id)

    async def heartbeat(self, device_id: str) -> bool:
        """
        Update heartbeat timestamp.
        Returns True if device was online, False otherwise.
        """
        now = time.time()

        # Check if device is online
        is_online = await self.is_online(device_id)
        if not is_online:
            return False

        # Update heartbeat with TTL
        await self.redis.set(
            f"{self.KEY_HEARTBEAT_PREFIX}{device_id}",
            str(now),
            ex=self.HEARTBEAT_TTL,
        )

        # Update session last_heartbeat
        session_key = f"{self.KEY_SESSION_PREFIX}{device_id}"
        session_data = await self.redis.get(session_key)
        if session_data:
            try:
                info = json.loads(session_data)
                info["last_heartbeat"] = now
                await self.redis.set(session_key, json.dumps(info), ex=self.SESSION_TTL)
            except json.JSONDecodeError:
                pass

        # Local fallback
        if device_id in self._local_sessions:
            self._local_sessions[device_id].last_heartbeat = now

        return True

    async def is_online(self, device_id: str) -> bool:
        """Check if a device is currently online."""
        # Check heartbeat key exists (has TTL)
        exists = await self.redis.exists(f"{self.KEY_HEARTBEAT_PREFIX}{device_id}")
        if exists:
            return True

        # Fallback to set membership
        return await self.redis.sismember(self.KEY_ONLINE_SET, device_id)

    async def get_online_devices(self) -> set[str]:
        """Get all online device IDs."""
        return await self.redis.smembers(self.KEY_ONLINE_SET)

    async def get_online_count(self) -> int:
        """Get count of online devices."""
        return await self.redis.scard(self.KEY_ONLINE_SET)

    async def get_presence_info(self, device_id: str) -> Optional[PresenceInfo]:
        """Get detailed presence info for a device."""
        session_data = await self.redis.get(f"{self.KEY_SESSION_PREFIX}{device_id}")
        if not session_data:
            return self._local_sessions.get(device_id)

        try:
            info = json.loads(session_data)
            return PresenceInfo(
                device_id=device_id,
                session_id=info.get("session_id", ""),
                connected_at=info.get("connected_at", 0),
                last_heartbeat=info.get("last_heartbeat", 0),
                agent_version=info.get("agent_version"),
                ip_address=info.get("ip_address"),
            )
        except json.JSONDecodeError:
            return None

    async def cleanup_stale(self) -> int:
        """
        Remove devices with expired heartbeats from online set.
        Call periodically to handle edge cases.
        Returns number of devices cleaned up.
        """
        online = await self.get_online_devices()
        cleaned = 0

        for device_id in online:
            hb_exists = await self.redis.exists(f"{self.KEY_HEARTBEAT_PREFIX}{device_id}")
            if not hb_exists:
                await self.redis.srem(self.KEY_ONLINE_SET, device_id)
                cleaned += 1
                logger.info("Cleaned up stale device: %s", device_id)

        return cleaned
