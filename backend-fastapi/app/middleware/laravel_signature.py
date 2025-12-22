from __future__ import annotations

import json
from typing import Any, Awaitable, Callable

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse, Response

from app.config import settings
from app.ws.canonical import canonicalize_json
from app.ws.signing import SignatureError, verify_ed25519_detached
from app.services.replay_protection import ReplayConfig, ReplayProtector, ReplayError


laravel_replay = ReplayProtector(
    ReplayConfig(
        redis_url=settings.redis_url,
        max_clock_skew_seconds=settings.max_clock_skew_seconds,
        require_seq=settings.require_laravel_seq,
        key_namespace="laravel",
    )
)


class LaravelSignatureMiddleware(BaseHTTPMiddleware):
    """Verifies Laravel→FastAPI signed requests for sensitive control-plane endpoints."""

    def __init__(self, app):
        super().__init__(app)

    async def dispatch(self, request: Request, call_next: Callable[[Request], Awaitable[Response]]) -> Response:
        if not settings.require_laravel_signature:
            return await call_next(request)

        # Protect Laravel->FastAPI control-plane endpoints.
        protected_paths = {
            "/api/v1/command/dispatch",
            "/api/v1/policy/push",
            "/api/v1/update/deploy",
            # Device key sync endpoint (Laravel is the authority).
            "/api/v1/admin/device-keys",
        }

        if request.method.upper() != "POST":
            return await call_next(request)

        # Allow prefix match for device-keys endpoint.
        if request.url.path not in protected_paths and not request.url.path.startswith("/api/v1/admin/device-keys/"):
            return await call_next(request)

        pubkey_b64 = settings.laravel_service_pubkey_b64
        if not pubkey_b64:
            return JSONResponse({"detail": "LARAVEL_SERVICE_PUBKEY_B64 not configured"}, status_code=500)

        sig_b64 = request.headers.get("X-Laravel-Signature")
        if not sig_b64:
            return JSONResponse({"detail": "Missing X-Laravel-Signature"}, status_code=401)

        raw = await request.body()
        try:
            payload: Any = json.loads(raw)
        except Exception:
            return JSONResponse({"detail": "Invalid JSON"}, status_code=400)

        msg = canonicalize_json(payload)

        try:
            verify_ed25519_detached(msg, sig_b64, pubkey_b64)
        except SignatureError:
            return JSONResponse({"detail": "Invalid signature"}, status_code=401)

        # Optional replay enforcement for Laravel->FastAPI requests.
        if settings.require_laravel_seq:
            try:
                seq = payload.get("seq")
                await laravel_replay.check_and_update_seq("laravel", seq if isinstance(seq, int) else None)

                ts = (
                    (payload.get("envelope") or {}).get("header") or {}
                ).get("timestamp")
                if isinstance(ts, str) and ts:
                    laravel_replay.validate_timestamp(ts)
            except ReplayError:
                return JSONResponse({"detail": "Replay detected"}, status_code=401)

        return await call_next(request)
