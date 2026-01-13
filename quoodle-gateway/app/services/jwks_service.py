import httpx


class JWKSService:
    def __init__(self, url: str) -> None:
        self.url = url
        self.cache: dict | None = None

    async def fetch(self) -> dict:
        if self.cache:
            return self.cache
        async with httpx.AsyncClient() as client:
            resp = await client.get(self.url, timeout=5.0)
            resp.raise_for_status()
            self.cache = resp.json()
            return self.cache
