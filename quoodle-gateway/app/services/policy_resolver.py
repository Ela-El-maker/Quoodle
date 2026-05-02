import json
from pathlib import Path
from typing import Any, Dict, Optional

from app.config import settings
from app.ws.protocol import compute_sig, iso_timestamp


class PolicyResolver:
    """
    Holds the latest policy bundle metadata and can build POLICY_UPDATE messages for agents.
    """

    def __init__(self) -> None:
        self._state_path = Path(settings.policy_state_path)
        self._current: Dict[str, Any] = {
            "policy_version": settings.policy_version,
            "policy_hash": settings.policy_hash,
            "policy_url": None,
            "effective_from": iso_timestamp(),
            "signature": None,
            "app_lock": None,
        }
        self._device_app_lock: Dict[str, Dict[str, Any]] = {}
        self._load_state()

    def current(self) -> Dict[str, Any]:
        return dict(self._current)

    def _persist_state(self) -> None:
        payload = {
            "current": self._current,
            "device_app_lock": self._device_app_lock,
        }
        try:
            self._state_path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self._state_path.with_suffix(self._state_path.suffix + ".tmp")
            tmp.write_text(json.dumps(payload, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
            tmp.replace(self._state_path)
        except Exception:
            # Best-effort durability; never break runtime policy flow because of disk IO.
            return

    def _load_state(self) -> None:
        try:
            if not self._state_path.exists():
                return
            raw = json.loads(self._state_path.read_text(encoding="utf-8"))
            if not isinstance(raw, dict):
                return
            current = raw.get("current")
            if isinstance(current, dict):
                self._current = {
                    **self._current,
                    **current,
                }
            scoped = raw.get("device_app_lock")
            if isinstance(scoped, dict):
                loaded: Dict[str, Dict[str, Any]] = {}
                for device_id, bundle in scoped.items():
                    if isinstance(device_id, str) and isinstance(bundle, dict):
                        loaded[device_id] = bundle
                self._device_app_lock = loaded
        except Exception:
            # Ignore corrupt cache and continue with defaults.
            return

    def update(
        self,
        policy_version: str,
        policy_hash: str,
        policy_url: str,
        signed_at: str,
        signature: str,
        app_lock: Optional[Dict[str, Any]] = None,
        target_device_ids: Optional[list[str]] = None,
    ) -> Dict[str, Any]:
        current_app_lock = self._current.get("app_lock")
        has_targets = bool(target_device_ids)
        if app_lock is not None and not has_targets:
            current_app_lock = app_lock
        if app_lock is not None and has_targets:
            for device_id in target_device_ids or []:
                self._device_app_lock[device_id] = app_lock
        self._current = {
            "policy_version": policy_version,
            "policy_hash": policy_hash,
            "policy_url": policy_url,
            "effective_from": signed_at or iso_timestamp(),
            "signature": signature,
            "app_lock": current_app_lock,
        }
        self._persist_state()
        return self.current()

    def build_message(self, device_id: Optional[str], session_id: Optional[str]) -> Dict[str, Any]:
        body = self.current()
        if device_id:
            scoped_app_lock = self._device_app_lock.get(device_id)
            if scoped_app_lock is not None:
                body = {
                    **body,
                    "app_lock": scoped_app_lock,
                }
        payload = {
            "type": "POLICY_UPDATE",
            "from": settings.controller_id,
            "device_id": device_id,
            "message_id": f"m-policy-{iso_timestamp()}",
            "session_id": session_id,
            "timestamp": iso_timestamp(),
            "body": body,
        }
        payload["sig"] = compute_sig(payload)
        return payload

    async def send_current(self, websocket, device_id: str, session_id: str) -> None:
        message = self.build_message(device_id, session_id)
        await websocket.send_json(message)
