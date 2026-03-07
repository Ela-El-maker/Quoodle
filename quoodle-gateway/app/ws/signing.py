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


def _decode_base64_padded(value: str, field_name: str) -> bytes:
    try:
        return base64.b64decode(value)
    except Exception:
        padding = (-len(value)) % 4
        try:
            return base64.b64decode(value + ("=" * padding))
        except Exception as exc:
            raise SignatureError(f"{field_name} is not valid base64") from exc


def verify_ed25519_detached(message: bytes, signature_b64: str, pubkey_b64: str) -> None:
    if not HAVE_PYNACL_VERIFY or VerifyKey is None:
        raise SignatureError("PyNaCl not installed; cannot verify Ed25519 signatures")

    if not isinstance(signature_b64, str) or not signature_b64:
        raise SignatureError("Missing signature")

    sig = _decode_base64_padded(signature_b64, "signature")
    pub = _decode_base64_padded(pubkey_b64, "pubkey")

    try:
        VerifyKey(pub).verify(message, sig)
    except Exception as exc:
        raise SignatureError("Ed25519 verification failed") from exc


def verify_ed25519_signature(payload: Dict[str, Any], pubkey_b64: str) -> None:
    if not HAVE_PYNACL_VERIFY or VerifyKey is None:
        raise SignatureError("PyNaCl not installed; cannot verify Ed25519 signatures")

    sig_b64 = payload.get("sig")
    if not isinstance(sig_b64, str) or not sig_b64:
        raise SignatureError("Missing sig")

    sig = _decode_base64_padded(sig_b64, "sig")
    pub = _decode_base64_padded(pubkey_b64, "pubkey")

    # Canonical bytes of full message excluding sig
    msg = canonicalize_json(strip_sig(payload))

    verify_ed25519_detached(msg, sig_b64, pubkey_b64)
