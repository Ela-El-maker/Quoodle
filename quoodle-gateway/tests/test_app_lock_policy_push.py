from types import SimpleNamespace

from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from app.state import manager


class _DummyWebSocket:
    def __init__(self) -> None:
        self.messages = []

    async def send_json(self, message):
        self.messages.append(message)


def _policy_payload():
    return {
        "policy_version": "2026-04-14",
        "policy_hash": "sha256:test-policy-hash",
        "policy_url": "control-plane://policy/app-lock",
        "signed_at": "2026-04-14T10:00:00Z",
        "signature": "sig-policy",
        "app_lock": {
            "enabled": True,
            "mode": "blocklist",
            "fail_mode": "open",
            "policy_version": "2026-04-14",
            "policy_hash": "sha256:test-policy-hash",
            "event_dedupe_sec": 30,
            "updated_at": "2026-04-14T10:00:00Z",
            "rules": [
                {
                    "rule_id": "rule-whatsapp",
                    "match_type": "basename",
                    "value": "whatsapp.exe",
                    "action": "block",
                    "priority": 100,
                    "expires_at": None,
                }
            ],
        },
    }


def test_policy_push_fans_out_app_lock_bundle(monkeypatch):
    client = TestClient(app)
    old_require = settings.require_laravel_signature
    try:
        settings.require_laravel_signature = False

        ws = _DummyWebSocket()
        entry = SimpleNamespace(websocket=ws, session_id="sess-1", device_id="PC001")

        async def _all_entries():
            return [entry]

        monkeypatch.setattr(manager, "all_entries", _all_entries)

        response = client.post("/api/v1/policy/push", json=_policy_payload())
        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "accepted"
        assert body["policy"]["app_lock"]["enabled"] is True
        assert body["policy"]["app_lock"]["rules"][0]["rule_id"] == "rule-whatsapp"

        assert len(ws.messages) == 1
        delivered = ws.messages[0]
        assert delivered["type"] == "POLICY_UPDATE"
        assert delivered["device_id"] == "PC001"
        assert delivered["session_id"] == "sess-1"
        assert delivered["body"]["app_lock"]["enabled"] is True
    finally:
        settings.require_laravel_signature = old_require


def test_policy_push_builds_per_entry_message(monkeypatch):
    client = TestClient(app)
    old_require = settings.require_laravel_signature
    try:
        settings.require_laravel_signature = False

        ws_a = _DummyWebSocket()
        ws_b = _DummyWebSocket()
        entry_a = SimpleNamespace(websocket=ws_a, session_id="sess-a", device_id="PC-A")
        entry_b = SimpleNamespace(websocket=ws_b, session_id="sess-b", device_id="PC-B")

        async def _all_entries():
            return [entry_a, entry_b]

        monkeypatch.setattr(manager, "all_entries", _all_entries)

        response = client.post("/api/v1/policy/push", json=_policy_payload())
        assert response.status_code == 200

        assert len(ws_a.messages) == 1
        assert len(ws_b.messages) == 1
        assert ws_a.messages[0]["device_id"] == "PC-A"
        assert ws_b.messages[0]["device_id"] == "PC-B"
        assert ws_a.messages[0]["session_id"] == "sess-a"
        assert ws_b.messages[0]["session_id"] == "sess-b"
    finally:
        settings.require_laravel_signature = old_require


def test_policy_push_targets_specific_devices_only(monkeypatch):
    client = TestClient(app)
    old_require = settings.require_laravel_signature
    try:
        settings.require_laravel_signature = False

        ws_a = _DummyWebSocket()
        ws_b = _DummyWebSocket()
        entry_a = SimpleNamespace(websocket=ws_a, session_id="sess-a", device_id="PC-A")
        entry_b = SimpleNamespace(websocket=ws_b, session_id="sess-b", device_id="PC-B")

        async def _all_entries():
            return [entry_a, entry_b]

        monkeypatch.setattr(manager, "all_entries", _all_entries)

        payload = _policy_payload()
        payload["target_device_ids"] = ["PC-B"]

        response = client.post("/api/v1/policy/push", json=payload)
        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "accepted"
        assert body["target_device_ids"] == ["PC-B"]
        assert body["delivered_count"] == 1

        assert len(ws_a.messages) == 0
        assert len(ws_b.messages) == 1
        assert ws_b.messages[0]["device_id"] == "PC-B"
    finally:
        settings.require_laravel_signature = old_require
