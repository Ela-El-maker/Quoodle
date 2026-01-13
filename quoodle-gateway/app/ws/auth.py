import time
from typing import Any, Dict, Optional

import httpx
from jose import JWTError, jwk, jwt

from app.config import settings


class JWKSCache:
    def __init__(self) -> None:
        self._jwks: Dict[str, Any] | None = None
        self._fetched_at: float | None = None
        self._ttl_seconds = 300

    async def get(self) -> Dict[str, Any]:
        now = time.time()
        if self._jwks and self._fetched_at and (now - self._fetched_at) < self._ttl_seconds:
            return self._jwks

        async with httpx.AsyncClient() as client:
            response = await client.get(settings.jwks_url, timeout=5.0)
            response.raise_for_status()
            jwks = response.json()

        self._jwks = jwks
        self._fetched_at = now
        return jwks


jwks_cache = JWKSCache()


async def validate_auth_jwt(token: str) -> Dict[str, Any]:
    jwks = await jwks_cache.get()
    unverified = jwt.get_unverified_header(token)
    kid = unverified.get("kid")
    if not kid:
        raise JWTError("Missing kid")

    keys = jwks.get("keys", [])
    match: Optional[Dict[str, Any]] = next((k for k in keys if k.get("kid") == kid), None)
    if not match:
        raise JWTError("Unknown kid")

    alg = match.get("alg", "PS256")
    key = jwk.construct(match, algorithm=alg)
    public_key = key.to_pem().decode("utf-8")

    return jwt.decode(
        token,
        public_key,
        algorithms=[alg],
        audience=settings.jwt_audience,
        issuer=settings.jwt_issuer,
    )
