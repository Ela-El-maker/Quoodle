from __future__ import annotations

import base64
from typing import Any, Dict, Optional

from app.config import settings
from app.ws.canonical import canonicalize_json

try:
    from nacl.signing import SigningKey

    HAVE_PYNACL_SIGN = True
except Exception:
    SigningKey = None  # type: ignore
    HAVE_PYNACL_SIGN = False


class ServiceSigningError(ValueError):
    pass


def _load_signing_key(sk_b64: str) -> "SigningKey":
    if not HAVE_PYNACL_SIGN or SigningKey is None:
        raise ServiceSigningError("PyNaCl not installed; cannot sign Ed25519")

    try:
        raw = base64.b64decode(sk_b64)
    except Exception as exc:
        raise ServiceSigningError("service private key is not valid base64") from exc

    # Accept either 32-byte seed or 64-byte libsodium secret key.
    if len(raw) == 32:
        seed = raw
    elif len(raw) == 64:
        seed = raw[:32]
    else:
        raise ServiceSigningError(f"unexpected private key length ({len(raw)})")

    return SigningKey(seed)


def sign_fastapi_to_laravel(payload: Dict[str, Any]) -> Optional[Dict[str, str]]:
    """Return headers for FastAPI→Laravel requests, or None if disabled.

    Spec: X-FastAPI-Signature: base64-ed25519
    Signature covers canonical JSON bytes of the webhook JSON payload.
    """

    if not settings.sign_laravel_webhooks:
        return None

    sk_b64 = settings.fastapi_service_private_key_b64
    if not sk_b64:
        raise ServiceSigningError("FASTAPI_SERVICE_PRIVATE_KEY_B64 not configured")

    msg = canonicalize_json(payload)
    key = _load_signing_key(sk_b64)
    sig = key.sign(msg).signature
    sig_b64 = base64.b64encode(sig).decode("ascii")
    return {"X-FastAPI-Signature": sig_b64}
