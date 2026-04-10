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
    agent_pubkey_b64: str | None = None


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
        agent_pubkey_b64: str | None = None,
    ) -> None:
        previous: ConnectionEntry | None = None
        async with self.lock:
            previous = self.active_connections.get(device_id)
            self.active_connections[device_id] = ConnectionEntry(
                websocket=websocket,
                session_id=session_id,
                device_id=device_id,
                agent_version=agent_version,
                os_build=os_build,
                attestation_hash=attestation_hash,
                connected_at=connected_at,
                agent_pubkey_b64=agent_pubkey_b64,
            )
        # Supersede stale socket for the same device to avoid dual-session races.
        if previous is not None and previous.websocket is not websocket:
            try:
                await previous.websocket.close(code=1000, reason="Superseded by new session")
            except Exception:
                pass

    async def unregister(
        self,
        device_id: str,
        session_id: str | None = None,
        websocket: WebSocket | None = None,
    ) -> Optional[ConnectionEntry]:
        async with self.lock:
            current = self.active_connections.get(device_id)
            if current is None:
                return None
            # Ignore stale disconnects from older sessions/sockets.
            if session_id is not None and current.session_id != session_id:
                return None
            if websocket is not None and current.websocket is not websocket:
                return None
            return self.active_connections.pop(device_id, None)

    async def get(self, device_id: str) -> Optional[ConnectionEntry]:
        async with self.lock:
            return self.active_connections.get(device_id)

    async def all_entries(self) -> List[ConnectionEntry]:
        async with self.lock:
            return list(self.active_connections.values())
