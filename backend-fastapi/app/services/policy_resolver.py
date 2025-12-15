from typing import Any, Dict, Optional

from app.config import settings
from app.ws.protocol import compute_sig, iso_timestamp


class PolicyResolver:
    """
    Holds the latest policy bundle metadata and can build POLICY_UPDATE messages for agents.
    """

    def __init__(self) -> None:
        self._current: Dict[str, Any] = {
            "policy_version": "policy-placeholder",
            "policy_hash": "sha256:policy_placeholder",
            "policy_url": None,
            "effective_from": iso_timestamp(),
            "signature": None,
        }

    def current(self) -> Dict[str, Any]:
        return dict(self._current)

    def update(self, policy_version: str, policy_hash: str, policy_url: str, signed_at: str, signature: str) -> Dict[str, Any]:
        self._current = {
            "policy_version": policy_version,
            "policy_hash": policy_hash,
            "policy_url": policy_url,
            "effective_from": signed_at or iso_timestamp(),
            "signature": signature,
        }
        return self.current()

    def build_message(self, device_id: Optional[str], session_id: Optional[str]) -> Dict[str, Any]:
        payload = {
            "type": "POLICY_UPDATE",
            "from": settings.controller_id,
            "device_id": device_id,
            "message_id": f"m-policy-{iso_timestamp()}",
            "session_id": session_id,
            "timestamp": iso_timestamp(),
            "body": self.current(),
        }
        payload["sig"] = compute_sig(payload)
        return payload

    async def send_current(self, websocket, device_id: str, session_id: str) -> None:
        message = self.build_message(device_id, session_id)
        await websocket.send_json(message)
