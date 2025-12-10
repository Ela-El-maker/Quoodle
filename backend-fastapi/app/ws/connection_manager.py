import asyncio
from dataclasses import dataclass
from typing import Dict, List, Optional

from fastapi import WebSocket


@dataclass
class ConnectionEntry:
    websocket: WebSocket
    session_id: str
    device_id: str
    agent_version: str | None
    os_build: str | None
    attestation_hash: str | None
    connected_at: str


class ConnectionManager:
    def __init__(self) -> None:
        self.active_connections: Dict[str, ConnectionEntry] = {}
        self.lock = asyncio.Lock()

    async def register(
        self,
        device_id: str,
        websocket: WebSocket,
        session_id: str,
        agent_version: str | None,
        os_build: str | None,
        attestation_hash: str | None,
        connected_at: str,
    ) -> None:
        async with self.lock:
            self.active_connections[device_id] = ConnectionEntry(
                websocket=websocket,
                session_id=session_id,
                device_id=device_id,
                agent_version=agent_version,
                os_build=os_build,
                attestation_hash=attestation_hash,
                connected_at=connected_at,
            )

    async def unregister(self, device_id: str) -> Optional[ConnectionEntry]:
        async with self.lock:
            return self.active_connections.pop(device_id, None)

    async def get(self, device_id: str) -> Optional[ConnectionEntry]:
        async with self.lock:
            return self.active_connections.get(device_id)

    async def all_entries(self) -> List[ConnectionEntry]:
        async with self.lock:
            return list(self.active_connections.values())
