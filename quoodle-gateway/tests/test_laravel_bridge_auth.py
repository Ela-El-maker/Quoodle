import base64

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from app.ws.canonical import canonicalize_json


@pytest.fixture()
def client():
    return TestClient(app)


def _sample_dispatch_payload():
    return {
        "command_id": "CMD-123",
        "device_id": "PC001",
        "trace_id": "TRACE-111",
        "seq": 1,
        "method": "ping",
        "params": {},
        "sensitive": False,
        "policy": {"policy_version": "policy-2025-11-01", "policy_hash": "sha256:deadbeef"},
        "compliance": {"result": "allow"},
        "envelope": {
            "header": {
                "version": "1.1",
                "timestamp": "2025-11-22T12:00:00Z",
                "ttl_seconds": 300,
                "priority": "normal",
                "requires_ack": True,
                "long_running": False,
            },
            "body": {"method": "ping", "params": {}, "sensitive": False},
            "meta": {
                "origin_user_id": "UID001",
                "enc": "none",
                "enc_key_id": None,
                "policy_version": "policy-2025-11-01",
            },
            "sig": "sig_laravel",
        },
    }


def test_dispatch_requires_signature_when_enabled(client):
    old_require = settings.require_laravel_signature
    old_pub = settings.laravel_service_pubkey_b64
    try:
        settings.require_laravel_signature = True
        settings.laravel_service_pubkey_b64 = base64.b64encode(b"x" * 32).decode("ascii")

        resp = client.post("/api/v1/command/dispatch", json=_sample_dispatch_payload())
        assert resp.status_code == 401
    finally:
        settings.require_laravel_signature = old_require
        settings.laravel_service_pubkey_b64 = old_pub


def test_dispatch_accepts_valid_signature(client):
    pytest.importorskip("nacl")
    from nacl.signing import SigningKey

    signing_key = SigningKey.generate()
    verify_key = signing_key.verify_key

    old_require = settings.require_laravel_signature
    old_pub = settings.laravel_service_pubkey_b64
    try:
        settings.require_laravel_signature = True
        settings.laravel_service_pubkey_b64 = base64.b64encode(bytes(verify_key)).decode("ascii")

        payload = _sample_dispatch_payload()
        msg = canonicalize_json(payload)
        sig = signing_key.sign(msg).signature
        sig_b64 = base64.b64encode(sig).decode("ascii")

        resp = client.post(
            "/api/v1/command/dispatch",
            json=payload,
            headers={"X-Laravel-Signature": sig_b64},
        )
        assert resp.status_code == 200
        body = resp.json()
        assert "status" in body
    finally:
        settings.require_laravel_signature = old_require
        settings.laravel_service_pubkey_b64 = old_pub


def test_dispatch_rejects_invalid_signature(client):
    pytest.importorskip("nacl")
    from nacl.signing import SigningKey

    signing_key = SigningKey.generate()
    wrong_key = SigningKey.generate()

    old_require = settings.require_laravel_signature
    old_pub = settings.laravel_service_pubkey_b64
    try:
        settings.require_laravel_signature = True
        settings.laravel_service_pubkey_b64 = base64.b64encode(bytes(wrong_key.verify_key)).decode("ascii")

        payload = _sample_dispatch_payload()
        msg = canonicalize_json(payload)
        sig = signing_key.sign(msg).signature
        sig_b64 = base64.b64encode(sig).decode("ascii")

        resp = client.post(
            "/api/v1/command/dispatch",
            json=payload,
            headers={"X-Laravel-Signature": sig_b64},
        )
        assert resp.status_code == 401
    finally:
        settings.require_laravel_signature = old_require
        settings.laravel_service_pubkey_b64 = old_pub
