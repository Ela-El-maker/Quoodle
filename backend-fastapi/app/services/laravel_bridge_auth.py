from __future__ import annotations

import json
from typing import Any

from fastapi import HTTPException, Request

from app.config import settings
from app.ws.canonical import canonicalize_json
from app.ws.signing import SignatureError, verify_ed25519_detached


async def require_laravel_signature(request: Request) -> None:
    """Verify that inbound Laravel→FastAPI requests are authenticated.

    Spec: docs/specs/FastAPI ↔ Laravel (REST + Webhook Control Channel).json
      - header: X-Laravel-Signature: base64-ed25519
      - verify: FastAPI verifies using Laravel’s public key

    We verify the signature over canonical JSON bytes of the request body.
    """

    if not settings.require_laravel_signature:
        return

    pubkey_b64 = settings.laravel_service_pubkey_b64
    if not pubkey_b64:
        # Misconfiguration: endpoint is protected but key not configured.
        raise HTTPException(status_code=500, detail="LARAVEL_SERVICE_PUBKEY_B64 not configured")

    sig_b64 = request.headers.get("X-Laravel-Signature")
    if not sig_b64:
        raise HTTPException(status_code=401, detail="Missing X-Laravel-Signature")

    raw = await request.body()
    try:
        payload: Any = json.loads(raw)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON")

    msg = canonicalize_json(payload)

    try:
        verify_ed25519_detached(msg, sig_b64, pubkey_b64)
    except SignatureError:
        raise HTTPException(status_code=401, detail="Invalid signature")
