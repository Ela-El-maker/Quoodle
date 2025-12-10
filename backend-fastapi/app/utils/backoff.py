import asyncio


async def with_backoff(fn, retries: int = 3, base_delay: float = 0.5):
    attempt = 0
    while attempt < retries:
        try:
            return await fn()
        except Exception:
            attempt += 1
            await asyncio.sleep(base_delay * (2 ** attempt))
    raise RuntimeError("max retries exceeded")
