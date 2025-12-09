import asyncio
from dataclasses import dataclass
from typing import Dict, Optional

from fastapi import WebSocket


@dataclass
class ConnectionEntry:
    websocket: WebSocket
    session_id: str


class ConnectionManager:
    def __init__(self) -> None:
        self.active_connections: Dict[str, ConnectionEntry] = {}
        self.lock = asyncio.Lock()

    async def register(self, device_id: str, websocket: WebSocket, session_id: str) -> None:
        async with self.lock:
            self.active_connections[device_id] = ConnectionEntry(websocket=websocket, session_id=session_id)

    async def unregister(self, device_id: str) -> None:
        async with self.lock:
            self.active_connections.pop(device_id, None)

    async def get(self, device_id: str) -> Optional[ConnectionEntry]:
        async with self.lock:
            return self.active_connections.get(device_id)
