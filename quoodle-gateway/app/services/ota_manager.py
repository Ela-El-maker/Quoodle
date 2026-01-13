from typing import Any, Dict, Optional, List

from app.config import settings
from app.ws.protocol import compute_sig, iso_timestamp


class OTAManager:
    def __init__(self) -> None:
        self._latest: Optional[Dict[str, Any]] = None

    def set_release(self, manifest: Dict[str, Any]) -> None:
        self._latest = manifest

    def latest(self) -> Optional[Dict[str, Any]]:
        return self._latest

    def build_announce(self, device_id: Optional[str], session_id: Optional[str]) -> Optional[Dict[str, Any]]:
        if not self._latest:
            return None
        payload = {
            "type": "UPDATE_ANNOUNCE",
            "from": settings.controller_id,
            "device_id": device_id,
            "message_id": f"m-update-{iso_timestamp()}",
            "session_id": session_id,
            "timestamp": iso_timestamp(),
            "body": self._latest,
        }
        payload["sig"] = compute_sig(payload)
        return payload

    async def send_latest(self, websocket, device_id: str, session_id: str) -> None:
        message = self.build_announce(device_id, session_id)
        if message:
            await websocket.send_json(message)
