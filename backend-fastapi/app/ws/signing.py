from __future__ import annotations

import base64
from typing import Any, Dict

try:
    from nacl.signing import VerifyKey

    HAVE_PYNACL_VERIFY = True
except Exception:
    VerifyKey = None  # type: ignore
    HAVE_PYNACL_VERIFY = False

from app.ws.canonical import canonicalize_json, strip_sig


class SignatureError(ValueError):
    pass


def verify_ed25519_signature(payload: Dict[str, Any], pubkey_b64: str) -> None:
    if not HAVE_PYNACL_VERIFY or VerifyKey is None:
        raise SignatureError("PyNaCl not installed; cannot verify Ed25519 signatures")

    sig_b64 = payload.get("sig")
    if not isinstance(sig_b64, str) or not sig_b64:
        raise SignatureError("Missing sig")

    try:
        sig = base64.b64decode(sig_b64)
    except Exception as exc:
        raise SignatureError("sig is not valid base64") from exc

    try:
        pub = base64.b64decode(pubkey_b64)
    except Exception as exc:
        raise SignatureError("pubkey is not valid base64") from exc

    # Canonical bytes of full message excluding sig
    msg = canonicalize_json(strip_sig(payload))

    try:
        VerifyKey(pub).verify(msg, sig)
    except Exception as exc:
        raise SignatureError("Ed25519 verification failed") from exc
