import asyncio
from typing import Dict
from fastapi import WebSocket


class ConnectionManager:
    def __init__(self) -> None:
        self.active_connections: Dict[str, WebSocket] = {}
        self.lock = asyncio.Lock()

    async def register(self, device_id: str, websocket: WebSocket) -> None:
        async with self.lock:
            self.active_connections[device_id] = websocket

    async def unregister(self, device_id: str) -> None:
        async with self.lock:
            self.active_connections.pop(device_id, None)

    async def get(self, device_id: str) -> WebSocket | None:
        async with self.lock:
            return self.active_connections.get(device_id)
