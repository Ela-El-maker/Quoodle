"""
Redis service for centralized async Redis connection management.

Provides connection pooling, automatic reconnection, and common operations.
Falls back to in-memory storage when Redis is unavailable (dev/test).
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from typing import Any, Callable, Optional

try:
    import redis.asyncio as aioredis
    from redis.asyncio import Redis
    from redis.asyncio.connection import ConnectionPool

    HAVE_REDIS = True
except ImportError:
    aioredis = None  # type: ignore
    Redis = None  # type: ignore
    ConnectionPool = None  # type: ignore
    HAVE_REDIS = False

logger = logging.getLogger(__name__)


@dataclass
class RedisConfig:
    """Redis connection configuration."""

    url: Optional[str] = None
    max_connections: int = 10
    socket_timeout: float = 5.0
    socket_connect_timeout: float = 5.0
    retry_on_timeout: bool = True
    health_check_interval: int = 30
    decode_responses: bool = True
    # Key prefix for namespacing
    key_prefix: str = "quoodle:"


class RedisService:
    """
    Centralized Redis service with connection pooling and fallback.

    Features:
    - Async connection pooling
    - Automatic reconnection
    - Health checks
    - Pub/Sub support
    - Fallback to in-memory for dev/test
    """

    def __init__(self, config: Optional[RedisConfig] = None) -> None:
        self._config = config or RedisConfig()
        self._pool: Optional[ConnectionPool] = None
        self._client: Optional[Redis] = None
        self._connected = False
        self._fallback_store: dict[str, Any] = {}
        self._pubsub_handlers: dict[str, list[Callable]] = {}
        self._pubsub_task: Optional[asyncio.Task] = None

    @property
    def is_connected(self) -> bool:
        """Check if Redis is connected."""
        return self._connected and self._client is not None

    @property
    def is_fallback_mode(self) -> bool:
        """Check if using in-memory fallback."""
        return not self._connected

    async def connect(self) -> bool:
        """
        Initialize Redis connection pool.
        Returns True if connected, False if using fallback.
        """
        if not HAVE_REDIS or not self._config.url:
            logger.warning("Redis not available, using in-memory fallback")
            return False

        try:
            self._pool = ConnectionPool.from_url(
                self._config.url,
                max_connections=self._config.max_connections,
                socket_timeout=self._config.socket_timeout,
                socket_connect_timeout=self._config.socket_connect_timeout,
                retry_on_timeout=self._config.retry_on_timeout,
                health_check_interval=self._config.health_check_interval,
                decode_responses=self._config.decode_responses,
            )
            self._client = Redis(connection_pool=self._pool)

            # Test connection
            await self._client.ping()
            self._connected = True
            logger.info("Redis connected: %s", self._config.url)
            return True

        except Exception as e:
            logger.error("Redis connection failed: %s", e)
            self._connected = False
            self._client = None
            self._pool = None
            return False

    async def disconnect(self) -> None:
        """Close Redis connection and cleanup."""
        if self._pubsub_task:
            self._pubsub_task.cancel()
            try:
                await self._pubsub_task
            except asyncio.CancelledError:
                pass
            self._pubsub_task = None

        if self._client:
            try:
                await self._client.aclose()
            except Exception:
                pass
            self._client = None

        if self._pool:
            try:
                await self._pool.disconnect()
            except Exception:
                pass
            self._pool = None

        self._connected = False
        logger.info("Redis disconnected")

    def _key(self, key: str) -> str:
        """Apply key prefix."""
        return f"{self._config.key_prefix}{key}"

    # =========================================================================
    # Basic Operations
    # =========================================================================

    async def set(
        self,
        key: str,
        value: str,
        ex: Optional[int] = None,
        px: Optional[int] = None,
        nx: bool = False,
        xx: bool = False,
    ) -> bool:
        """Set a key with optional expiry and conditions."""
        prefixed = self._key(key)

        if self._client and self._connected:
            try:
                result = await self._client.set(prefixed, value, ex=ex, px=px, nx=nx, xx=xx)
                return bool(result)
            except Exception as e:
                logger.error("Redis SET failed: %s", e)
                # Fall through to fallback

        # Fallback
        if nx and prefixed in self._fallback_store:
            return False
        if xx and prefixed not in self._fallback_store:
            return False
        self._fallback_store[prefixed] = value
        return True

    async def get(self, key: str) -> Optional[str]:
        """Get a key value."""
        prefixed = self._key(key)

        if self._client and self._connected:
            try:
                return await self._client.get(prefixed)
            except Exception as e:
                logger.error("Redis GET failed: %s", e)

        return self._fallback_store.get(prefixed)

    async def delete(self, *keys: str) -> int:
        """Delete one or more keys."""
        prefixed = [self._key(k) for k in keys]

        if self._client and self._connected:
            try:
                return await self._client.delete(*prefixed)
            except Exception as e:
                logger.error("Redis DELETE failed: %s", e)

        count = 0
        for k in prefixed:
            if k in self._fallback_store:
                del self._fallback_store[k]
                count += 1
        return count

    async def exists(self, *keys: str) -> int:
        """Check if keys exist."""
        prefixed = [self._key(k) for k in keys]

        if self._client and self._connected:
            try:
                return await self._client.exists(*prefixed)
            except Exception as e:
                logger.error("Redis EXISTS failed: %s", e)

        return sum(1 for k in prefixed if k in self._fallback_store)

    async def expire(self, key: str, seconds: int) -> bool:
        """Set expiry on a key."""
        prefixed = self._key(key)

        if self._client and self._connected:
            try:
                return await self._client.expire(prefixed, seconds)
            except Exception as e:
                logger.error("Redis EXPIRE failed: %s", e)

        # Fallback doesn't support expiry
        return prefixed in self._fallback_store

    async def incr(self, key: str) -> int:
        """Increment a key."""
        prefixed = self._key(key)

        if self._client and self._connected:
            try:
                return await self._client.incr(prefixed)
            except Exception as e:
                logger.error("Redis INCR failed: %s", e)

        val = int(self._fallback_store.get(prefixed, 0)) + 1
        self._fallback_store[prefixed] = str(val)
        return val

    # =========================================================================
    # Hash Operations
    # =========================================================================

    async def hset(self, name: str, key: str, value: str) -> int:
        """Set a hash field."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.hset(prefixed, key, value)
            except Exception as e:
                logger.error("Redis HSET failed: %s", e)

        if prefixed not in self._fallback_store:
            self._fallback_store[prefixed] = {}
        was_new = key not in self._fallback_store[prefixed]
        self._fallback_store[prefixed][key] = value
        return 1 if was_new else 0

    async def hget(self, name: str, key: str) -> Optional[str]:
        """Get a hash field."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.hget(prefixed, key)
            except Exception as e:
                logger.error("Redis HGET failed: %s", e)

        h = self._fallback_store.get(prefixed, {})
        return h.get(key) if isinstance(h, dict) else None

    async def hgetall(self, name: str) -> dict[str, str]:
        """Get all hash fields."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.hgetall(prefixed)
            except Exception as e:
                logger.error("Redis HGETALL failed: %s", e)

        h = self._fallback_store.get(prefixed, {})
        return dict(h) if isinstance(h, dict) else {}

    async def hdel(self, name: str, *keys: str) -> int:
        """Delete hash fields."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.hdel(prefixed, *keys)
            except Exception as e:
                logger.error("Redis HDEL failed: %s", e)

        h = self._fallback_store.get(prefixed, {})
        if not isinstance(h, dict):
            return 0
        count = 0
        for k in keys:
            if k in h:
                del h[k]
                count += 1
        return count

    # =========================================================================
    # List Operations (for queues)
    # =========================================================================

    async def lpush(self, name: str, *values: str) -> int:
        """Push values to the left of a list."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.lpush(prefixed, *values)
            except Exception as e:
                logger.error("Redis LPUSH failed: %s", e)

        if prefixed not in self._fallback_store:
            self._fallback_store[prefixed] = []
        lst = self._fallback_store[prefixed]
        for v in reversed(values):
            lst.insert(0, v)
        return len(lst)

    async def rpush(self, name: str, *values: str) -> int:
        """Push values to the right of a list."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.rpush(prefixed, *values)
            except Exception as e:
                logger.error("Redis RPUSH failed: %s", e)

        if prefixed not in self._fallback_store:
            self._fallback_store[prefixed] = []
        lst = self._fallback_store[prefixed]
        lst.extend(values)
        return len(lst)

    async def lpop(self, name: str, count: Optional[int] = None) -> Optional[str | list[str]]:
        """Pop from the left of a list."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.lpop(prefixed, count)
            except Exception as e:
                logger.error("Redis LPOP failed: %s", e)

        lst = self._fallback_store.get(prefixed, [])
        if not lst:
            return None
        if count is None:
            return lst.pop(0)
        result = []
        for _ in range(min(count, len(lst))):
            result.append(lst.pop(0))
        return result if result else None

    async def rpop(self, name: str, count: Optional[int] = None) -> Optional[str | list[str]]:
        """Pop from the right of a list."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.rpop(prefixed, count)
            except Exception as e:
                logger.error("Redis RPOP failed: %s", e)

        lst = self._fallback_store.get(prefixed, [])
        if not lst:
            return None
        if count is None:
            return lst.pop()
        result = []
        for _ in range(min(count, len(lst))):
            result.append(lst.pop())
        return result if result else None

    async def lrange(self, name: str, start: int, end: int) -> list[str]:
        """Get a range from a list."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.lrange(prefixed, start, end)
            except Exception as e:
                logger.error("Redis LRANGE failed: %s", e)

        lst = self._fallback_store.get(prefixed, [])
        # Redis uses inclusive end, Python doesn't
        if end == -1:
            return lst[start:]
        return lst[start : end + 1]

    async def llen(self, name: str) -> int:
        """Get list length."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.llen(prefixed)
            except Exception as e:
                logger.error("Redis LLEN failed: %s", e)

        lst = self._fallback_store.get(prefixed, [])
        return len(lst) if isinstance(lst, list) else 0

    async def ltrim(self, name: str, start: int, end: int) -> bool:
        """Trim a list to the specified range."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.ltrim(prefixed, start, end)
            except Exception as e:
                logger.error("Redis LTRIM failed: %s", e)

        lst = self._fallback_store.get(prefixed, [])
        if isinstance(lst, list):
            if end == -1:
                self._fallback_store[prefixed] = lst[start:]
            else:
                self._fallback_store[prefixed] = lst[start : end + 1]
        return True

    # =========================================================================
    # Set Operations (for presence tracking)
    # =========================================================================

    async def sadd(self, name: str, *values: str) -> int:
        """Add members to a set."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.sadd(prefixed, *values)
            except Exception as e:
                logger.error("Redis SADD failed: %s", e)

        if prefixed not in self._fallback_store:
            self._fallback_store[prefixed] = set()
        s = self._fallback_store[prefixed]
        added = len(set(values) - s)
        s.update(values)
        return added

    async def srem(self, name: str, *values: str) -> int:
        """Remove members from a set."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.srem(prefixed, *values)
            except Exception as e:
                logger.error("Redis SREM failed: %s", e)

        s = self._fallback_store.get(prefixed, set())
        if not isinstance(s, set):
            return 0
        removed = len(set(values) & s)
        s -= set(values)
        return removed

    async def sismember(self, name: str, value: str) -> bool:
        """Check if value is in set."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.sismember(prefixed, value)
            except Exception as e:
                logger.error("Redis SISMEMBER failed: %s", e)

        s = self._fallback_store.get(prefixed, set())
        return value in s if isinstance(s, set) else False

    async def smembers(self, name: str) -> set[str]:
        """Get all members of a set."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.smembers(prefixed)
            except Exception as e:
                logger.error("Redis SMEMBERS failed: %s", e)

        s = self._fallback_store.get(prefixed, set())
        return set(s) if isinstance(s, set) else set()

    async def scard(self, name: str) -> int:
        """Get set cardinality."""
        prefixed = self._key(name)

        if self._client and self._connected:
            try:
                return await self._client.scard(prefixed)
            except Exception as e:
                logger.error("Redis SCARD failed: %s", e)

        s = self._fallback_store.get(prefixed, set())
        return len(s) if isinstance(s, set) else 0

    # =========================================================================
    # Pub/Sub Operations
    # =========================================================================

    async def publish(self, channel: str, message: str) -> int:
        """Publish a message to a channel."""
        prefixed = self._key(channel)

        if self._client and self._connected:
            try:
                return await self._client.publish(prefixed, message)
            except Exception as e:
                logger.error("Redis PUBLISH failed: %s", e)

        # Fallback: call handlers directly
        handlers = self._pubsub_handlers.get(channel, [])
        for handler in handlers:
            try:
                await handler(channel, message)
            except Exception as e:
                logger.error("Pub/sub handler error: %s", e)
        return len(handlers)

    async def subscribe(self, channel: str, handler: Callable[[str, str], Any]) -> None:
        """Subscribe to a channel with a handler."""
        if channel not in self._pubsub_handlers:
            self._pubsub_handlers[channel] = []
        self._pubsub_handlers[channel].append(handler)

        if self._client and self._connected and not self._pubsub_task:
            self._pubsub_task = asyncio.create_task(self._pubsub_loop())

    async def _pubsub_loop(self) -> None:
        """Background task for Redis pub/sub."""
        if not self._client:
            return

        try:
            pubsub = self._client.pubsub()
            channels = [self._key(ch) for ch in self._pubsub_handlers.keys()]
            if channels:
                await pubsub.subscribe(*channels)

            async for message in pubsub.listen():
                if message["type"] == "message":
                    channel = message["channel"]
                    # Remove prefix to get original channel name
                    if channel.startswith(self._config.key_prefix):
                        channel = channel[len(self._config.key_prefix) :]
                    data = message["data"]
                    handlers = self._pubsub_handlers.get(channel, [])
                    for handler in handlers:
                        try:
                            await handler(channel, data)
                        except Exception as e:
                            logger.error("Pub/sub handler error: %s", e)

        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.error("Pub/sub loop error: %s", e)

    # =========================================================================
    # Lua Script Execution
    # =========================================================================

    async def eval(self, script: str, numkeys: int, *args: Any) -> Any:
        """Execute a Lua script."""
        if self._client and self._connected:
            try:
                return await self._client.eval(script, numkeys, *args)
            except Exception as e:
                logger.error("Redis EVAL failed: %s", e)
                raise

        raise RuntimeError("Lua scripts not supported in fallback mode")

    # =========================================================================
    # Health Check
    # =========================================================================

    async def ping(self) -> bool:
        """Check Redis connectivity."""
        if self._client and self._connected:
            try:
                return await self._client.ping()
            except Exception:
                self._connected = False
                return False
        return False


# Global singleton instance
_redis_service: Optional[RedisService] = None


def get_redis_service() -> RedisService:
    """Get the global Redis service instance."""
    global _redis_service
    if _redis_service is None:
        _redis_service = RedisService()
    return _redis_service


async def init_redis(config: Optional[RedisConfig] = None) -> RedisService:
    """Initialize and connect the global Redis service."""
    global _redis_service
    _redis_service = RedisService(config)
    await _redis_service.connect()
    return _redis_service


async def close_redis() -> None:
    """Close the global Redis service."""
    global _redis_service
    if _redis_service:
        await _redis_service.disconnect()
        _redis_service = None
