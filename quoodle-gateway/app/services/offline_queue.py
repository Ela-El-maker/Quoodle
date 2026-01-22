"""
Offline message queue with Redis-backed persistence.

Stores messages for offline devices until they reconnect.
Falls back to in-memory storage when Redis is unavailable.
"""

from __future__ import annotations

import json
import logging
import time
from datetime import datetime
from collections import defaultdict, deque
from typing import Any, Deque, Dict, List, Optional

from app.services.redis_service import RedisService, get_redis_service

logger = logging.getLogger(__name__)


class OfflineQueue:
    """
    Queue messages for offline devices with Redis persistence.

    Features:
    - Persistent storage across gateway restarts
    - Per-device queue with configurable max size
    - FIFO ordering
    - Priority support
    - TTL for messages
    """

    # Redis keys
    KEY_PREFIX = "offline:queue:"
    KEY_META_PREFIX = "offline:meta:"

    # Default limits
    DEFAULT_MAX_PER_DEVICE = 200
    DEFAULT_MESSAGE_TTL = 86400  # 24 hours

    def __init__(
        self,
        max_per_device: int = DEFAULT_MAX_PER_DEVICE,
        message_ttl: int = DEFAULT_MESSAGE_TTL,
        redis: Optional[RedisService] = None,
    ) -> None:
        self._max = max_per_device
        self._ttl = message_ttl
        self._redis = redis
        # In-memory fallback
        self._local_queues: Dict[str, Deque[Dict[str, Any]]] = defaultdict(deque)

    @property
    def redis(self) -> RedisService:
        """Get Redis service, using global instance if not injected."""
        if self._redis is None:
            self._redis = get_redis_service()
        return self._redis

    def _queue_key(self, device_id: str) -> str:
        """Get Redis key for device queue."""
        return f"{self.KEY_PREFIX}{device_id}"

    def _parse_iso8601(self, ts: str) -> Optional[float]:
        try:
            if ts.endswith("Z"):
                ts = ts[:-1] + "+00:00"
            dt = datetime.fromisoformat(ts)
            return dt.timestamp()
        except Exception:
            return None

    def _compute_expires_at(self, message: Dict[str, Any]) -> Optional[float]:
        envelope = message.get("envelope") or {}
        header = envelope.get("header") or {}
        ts = header.get("timestamp")
        ttl = header.get("ttl_seconds")
        if isinstance(ts, str) and isinstance(ttl, int):
            base = self._parse_iso8601(ts)
            if base is not None:
                return base + ttl
        return None

    async def enqueue(
        self,
        device_id: str,
        message: Dict[str, Any],
        priority: int = 0,
    ) -> bool:
        """
        Add a message to the device's offline queue.
        Higher priority messages are delivered first on drain.

        Returns True if message was queued, False if queue was full and oldest was dropped.
        """
        queue_key = self._queue_key(device_id)

        # Wrap message with metadata
        expires_at = self._compute_expires_at(message)
        envelope = json.dumps(
            {
                "priority": priority,
                "message": message,
                "enqueued_at": time.time(),
                "expires_at": expires_at,
            }
        )

        # Use Redis if available
        if self.redis.is_connected:
            try:
                # Get current queue length
                length = await self.redis.llen(queue_key)

                # Trim if over limit (remove oldest from front)
                dropped = False
                if length >= self._max:
                    await self.redis.lpop(queue_key)
                    dropped = True

                # Add new message to end
                await self.redis.rpush(queue_key, envelope)

                # Set/refresh TTL on queue
                await self.redis.expire(queue_key, self._ttl)

                if dropped:
                    logger.warning(
                        "Offline queue full for %s, dropped oldest message", device_id
                    )
                return not dropped

            except Exception as e:
                logger.error("Redis enqueue failed: %s", e)
                # Fall through to local fallback

        # Local fallback
        queue = self._local_queues[device_id]
        dropped = False
        if len(queue) >= self._max:
            queue.popleft()
            dropped = True
        queue.append({"priority": priority, "message": message, "expires_at": expires_at})
        return not dropped

    async def drain(self, device_id: str) -> List[Dict[str, Any]]:
        """
        Retrieve and remove all queued messages for a device.
        Messages are returned sorted by priority (highest first), then FIFO.
        """
        queue_key = self._queue_key(device_id)

        # Use Redis if available
        if self.redis.is_connected:
            try:
                # Get all messages
                raw_messages = await self.redis.lrange(queue_key, 0, -1)
                if not raw_messages:
                    return []

                # Delete the queue
                await self.redis.delete(queue_key)

                # Parse and sort by priority
                messages = []
                for raw in raw_messages:
                    try:
                        envelope = json.loads(raw)
                        expires_at = envelope.get("expires_at")
                        if isinstance(expires_at, (int, float)) and time.time() > expires_at:
                            continue
                        messages.append(
                            {
                                "priority": envelope.get("priority", 0),
                                "message": envelope.get("message", {}),
                            }
                        )
                    except json.JSONDecodeError:
                        logger.warning("Invalid message in queue: %s", raw[:100])

                # Sort by priority descending (higher priority first)
                messages.sort(key=lambda m: m["priority"], reverse=True)

                logger.info(
                    "Drained %d messages for device %s", len(messages), device_id
                )
                return [m["message"] for m in messages]

            except Exception as e:
                logger.error("Redis drain failed: %s", e)
                # Fall through to local fallback

        # Local fallback
        queue = self._local_queues.get(device_id)
        if not queue:
            return []

        items = list(queue)
        queue.clear()

        # Sort by priority
        items.sort(key=lambda m: m.get("priority", 0), reverse=True)
        now = time.time()
        filtered = []
        for item in items:
            expires_at = item.get("expires_at")
            if isinstance(expires_at, (int, float)) and now > expires_at:
                continue
            filtered.append(item)
        return [m["message"] for m in filtered]

    async def peek(self, device_id: str, count: int = 10) -> List[Dict[str, Any]]:
        """
        Peek at queued messages without removing them.
        """
        queue_key = self._queue_key(device_id)

        if self.redis.is_connected:
            try:
                raw_messages = await self.redis.lrange(queue_key, 0, count - 1)
                messages = []
                for raw in raw_messages:
                    try:
                        envelope = json.loads(raw)
                        messages.append(envelope.get("message", {}))
                    except json.JSONDecodeError:
                        pass
                return messages
            except Exception as e:
                logger.error("Redis peek failed: %s", e)

        # Local fallback
        queue = self._local_queues.get(device_id)
        if not queue:
            return []
        return [m["message"] for m in list(queue)[:count]]

    async def size(self, device_id: str) -> int:
        """Get number of queued messages for a device."""
        queue_key = self._queue_key(device_id)

        if self.redis.is_connected:
            try:
                return await self.redis.llen(queue_key)
            except Exception as e:
                logger.error("Redis size failed: %s", e)

        queue = self._local_queues.get(device_id)
        return len(queue) if queue else 0

    async def clear(self, device_id: str) -> int:
        """Clear all messages for a device. Returns count of cleared messages."""
        queue_key = self._queue_key(device_id)

        if self.redis.is_connected:
            try:
                count = await self.redis.llen(queue_key)
                await self.redis.delete(queue_key)
                return count
            except Exception as e:
                logger.error("Redis clear failed: %s", e)

        queue = self._local_queues.get(device_id)
        if queue:
            count = len(queue)
            queue.clear()
            return count
        return 0

    async def get_queued_devices(self) -> List[str]:
        """
        Get list of device IDs that have queued messages.
        Note: Only works reliably with Redis due to key scanning.
        """
        if self.redis.is_connected and self.redis._client:
            try:
                # Scan for queue keys
                prefix = self.redis._key(self.KEY_PREFIX)
                cursor = 0
                devices = []
                while True:
                    cursor, keys = await self.redis._client.scan(
                        cursor, match=f"{prefix}*", count=100
                    )
                    for key in keys:
                        # Extract device_id from key
                        if key.startswith(prefix):
                            device_id = key[len(prefix) :]
                            devices.append(device_id)
                    if cursor == 0:
                        break
                return devices
            except Exception as e:
                logger.error("Redis scan failed: %s", e)

        # Local fallback
        return [
            device_id
            for device_id, queue in self._local_queues.items()
            if len(queue) > 0
        ]

    async def get_total_queued(self) -> int:
        """Get total number of messages across all devices."""
        devices = await self.get_queued_devices()
        total = 0
        for device_id in devices:
            total += await self.size(device_id)
        return total
