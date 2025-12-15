import asyncio
from typing import Any, Dict


class EventBus:
    """
    Lightweight async event publisher placeholder. Replace with Kafka/Redis Streams producer.
    """

    async def publish(self, topic: str, payload: Dict[str, Any]) -> None:
        # Placeholder for structured logging/metrics
        await asyncio.sleep(0)
        return
