import asyncio
import logging
import signal
from typing import Optional

from app.config import settings
from app.services.redis_service import get_redis_service

logger = logging.getLogger(__name__)

# Queue name for incoming telemetry
TELEMETRY_QUEUE = f"{settings.redis_key_prefix}telemetry_queue"


class TelemetryWorker:
    """
    Worker that consumes telemetry data from Redis queue and persists it.
    Currently mocks persistence to log/stdout.
    """

    def __init__(self):
        self.running = False
        self.redis = get_redis_service()

    async def start(self):
        """Start the worker loop."""
        self.running = True
        logger.info("Telemetry Worker starting...")
        
        # Ensure Redis is connected
        if not self.redis.is_connected:
            await self.redis.connect()

        logger.info(f"Listening on queue: {TELEMETRY_QUEUE}")

        while self.running:
            try:
                # Blocking pop with timeout to allow checking self.running
                # BLPOP returns (key, value) tuple or None
                # Note: using non-blocking lpop with sleep for simpler fallback compatibility
                # in a real production system with real Redis, we'd use blpop
                
                item = await self.redis.lpop(TELEMETRY_QUEUE)
                
                if item:
                    await self.process_item(item)
                else:
                    # Empty queue, sleep briefly
                    await asyncio.sleep(1.0)

            except asyncio.CancelledError:
                logger.info("Worker task cancelled")
                break
            except Exception as e:
                logger.error(f"Worker loop error: {e}")
                await asyncio.sleep(5.0)  # Backoff on error

        logger.info("Telemetry Worker stopped")

    async def process_item(self, item: str):
        """Process a single telemetry item."""
        try:
            # Here we would parse JSON and save to database (Postgres/TimescaleDB)
            # For now, we just log it as "Persisted"
            logger.info(f" [x] Persisted telemetry: {item[:100]}...")
        except Exception as e:
            logger.error(f"Failed to process item: {e}")

    async def stop(self):
        """Signal worker to stop."""
        self.running = False


async def run_worker():
    """Main entry for standalone worker execution."""
    # Configure basic logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )
    
    worker = TelemetryWorker()
    
    # Handle signals for graceful shutdown
    loop = asyncio.get_running_loop()
    stop_event = asyncio.Event()

    def signal_handler():
        logger.info("Shutdown signal received")
        stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, signal_handler)

    # Run worker in background task
    worker_task = asyncio.create_task(worker.start())

    # Wait for stop signal
    await stop_event.wait()
    
    # Shutdown
    await worker.stop()
    await worker_task
    await get_redis_service().disconnect()


if __name__ == "__main__":
    asyncio.run(run_worker())
