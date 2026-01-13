"""
Event bus for publishing domain events across services.

Uses Redis Pub/Sub for distributed event delivery across multiple gateway instances.
Falls back to local async event dispatch when Redis is unavailable.
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional
from uuid import uuid4

from app.services.redis_service import RedisService, get_redis_service

logger = logging.getLogger(__name__)


# Event handler type
EventHandler = Callable[[str, Dict[str, Any]], Any]


class EventBus:
    """
    Async event bus with Redis Pub/Sub for distributed deployment.

    Features:
    - Distributed pub/sub across gateway instances
    - Local handler registration
    - Event envelope with metadata
    - Topic-based routing
    - Fallback to local dispatch
    """

    # Standard event topics
    TOPIC_DEVICE_ONLINE = "device.online"
    TOPIC_DEVICE_OFFLINE = "device.offline"
    TOPIC_DEVICE_HEARTBEAT = "device.heartbeat"
    TOPIC_COMMAND_SENT = "command.sent"
    TOPIC_COMMAND_ACK = "command.ack"
    TOPIC_COMMAND_RESULT = "command.result"
    TOPIC_TELEMETRY = "telemetry.received"
    TOPIC_ALERT = "alert.triggered"
    TOPIC_POLICY_UPDATE = "policy.updated"
    TOPIC_OTA_STATUS = "ota.status"

    def __init__(self, redis: Optional[RedisService] = None) -> None:
        self._redis = redis
        self._handlers: Dict[str, List[EventHandler]] = {}
        self._all_handlers: List[EventHandler] = []  # Handlers for all events

    @property
    def redis(self) -> RedisService:
        """Get Redis service, using global instance if not injected."""
        if self._redis is None:
            self._redis = get_redis_service()
        return self._redis

    def _build_envelope(
        self, topic: str, payload: Dict[str, Any], source: str = "gateway"
    ) -> Dict[str, Any]:
        """Build event envelope with metadata."""
        return {
            "event_id": str(uuid4()),
            "topic": topic,
            "source": source,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "payload": payload,
        }

    async def publish(
        self,
        topic: str,
        payload: Dict[str, Any],
        source: str = "gateway",
    ) -> int:
        """
        Publish an event to a topic.
        Returns number of subscribers that received the event.
        """
        envelope = self._build_envelope(topic, payload, source)
        message = json.dumps(envelope)

        subscribers = 0

        # Publish to Redis if available
        if self.redis.is_connected:
            try:
                subscribers = await self.redis.publish(f"events:{topic}", message)
                logger.debug(
                    "Published event %s to topic %s (%d Redis subscribers)",
                    envelope["event_id"],
                    topic,
                    subscribers,
                )
            except Exception as e:
                logger.error("Redis publish failed: %s", e)

        # Always dispatch to local handlers
        local_count = await self._dispatch_local(topic, envelope)
        subscribers += local_count

        return subscribers

    async def _dispatch_local(
        self, topic: str, envelope: Dict[str, Any]
    ) -> int:
        """Dispatch event to local handlers."""
        handlers = self._handlers.get(topic, []) + self._all_handlers
        if not handlers:
            return 0

        dispatched = 0
        for handler in handlers:
            try:
                result = handler(topic, envelope["payload"])
                if asyncio.iscoroutine(result):
                    await result
                dispatched += 1
            except Exception as e:
                logger.error(
                    "Event handler error for topic %s: %s",
                    topic,
                    e,
                    exc_info=True,
                )

        return dispatched

    def subscribe(self, topic: str, handler: EventHandler) -> None:
        """
        Subscribe a handler to a topic.
        Handler will be called with (topic, payload) for each event.
        """
        if topic not in self._handlers:
            self._handlers[topic] = []
        self._handlers[topic].append(handler)
        logger.debug("Subscribed handler to topic: %s", topic)

    def subscribe_all(self, handler: EventHandler) -> None:
        """Subscribe a handler to all events."""
        self._all_handlers.append(handler)
        logger.debug("Subscribed handler to all events")

    def unsubscribe(self, topic: str, handler: EventHandler) -> bool:
        """Unsubscribe a handler from a topic."""
        if topic in self._handlers and handler in self._handlers[topic]:
            self._handlers[topic].remove(handler)
            return True
        return False

    async def start_redis_subscription(self) -> None:
        """
        Start listening for Redis pub/sub events.
        Call this once on startup if using Redis.
        """
        if not self.redis.is_connected:
            logger.warning("Redis not connected, skipping pub/sub subscription")
            return

        # Subscribe to all event topics
        for topic in self._handlers.keys():
            await self.redis.subscribe(
                f"events:{topic}",
                self._redis_message_handler,
            )

        logger.info("Started Redis event subscriptions")

    async def _redis_message_handler(self, channel: str, message: str) -> None:
        """Handle messages from Redis pub/sub."""
        try:
            envelope = json.loads(message)
            topic = envelope.get("topic", "")
            await self._dispatch_local(topic, envelope)
        except json.JSONDecodeError:
            logger.error("Invalid JSON in event: %s", message[:100])
        except Exception as e:
            logger.error("Error handling Redis event: %s", e)

    # =========================================================================
    # Convenience methods for common events
    # =========================================================================

    async def emit_device_online(
        self, device_id: str, session_id: str, **kwargs: Any
    ) -> None:
        """Emit device online event."""
        await self.publish(
            self.TOPIC_DEVICE_ONLINE,
            {"device_id": device_id, "session_id": session_id, **kwargs},
        )

    async def emit_device_offline(self, device_id: str, reason: str = "") -> None:
        """Emit device offline event."""
        await self.publish(
            self.TOPIC_DEVICE_OFFLINE,
            {"device_id": device_id, "reason": reason},
        )

    async def emit_command_sent(
        self, device_id: str, command_id: str, method: str, **kwargs: Any
    ) -> None:
        """Emit command sent event."""
        await self.publish(
            self.TOPIC_COMMAND_SENT,
            {
                "device_id": device_id,
                "command_id": command_id,
                "method": method,
                **kwargs,
            },
        )

    async def emit_command_result(
        self,
        device_id: str,
        command_id: str,
        status: str,
        result_code: str = "",
        **kwargs: Any,
    ) -> None:
        """Emit command result event."""
        await self.publish(
            self.TOPIC_COMMAND_RESULT,
            {
                "device_id": device_id,
                "command_id": command_id,
                "status": status,
                "result_code": result_code,
                **kwargs,
            },
        )

    async def emit_telemetry(
        self, device_id: str, telemetry: Dict[str, Any]
    ) -> None:
        """Emit telemetry received event."""
        await self.publish(
            self.TOPIC_TELEMETRY,
            {"device_id": device_id, "telemetry": telemetry},
        )

    async def emit_alert(
        self, device_id: str, alert_type: str, severity: str, message: str, **kwargs: Any
    ) -> None:
        """Emit alert triggered event."""
        await self.publish(
            self.TOPIC_ALERT,
            {
                "device_id": device_id,
                "alert_type": alert_type,
                "severity": severity,
                "message": message,
                **kwargs,
            },
        )
