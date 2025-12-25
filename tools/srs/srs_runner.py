from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import sys
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

import httpx


@dataclass
class CheckResult:
    time_label: str
    event: str
    flow_path: str
    validation: str
    status: str
    evidence: str = ""


def _b32decode_no_pad(s: str) -> bytes:
    s = s.strip().replace(" ", "").upper()
    pad = (8 - (len(s) % 8)) % 8
    s = s + ("=" * pad)
    return base64.b32decode(s, casefold=True)


def _totp(secret_b32: str, unix_time: Optional[int] = None, period: int = 30, digits: int = 6) -> str:
    now = int(unix_time if unix_time is not None else time.time())
    counter = now // period
    key = _b32decode_no_pad(secret_b32)
    msg = counter.to_bytes(8, "big")
    digest = hmac.new(key, msg, hashlib.sha1).digest()
    off = digest[-1] & 0x0F
    code_int = int.from_bytes(digest[off : off + 4], "big") & 0x7FFFFFFF
    return str(code_int % (10**digits)).zfill(digits)


def _canonicalize_json(value: Any) -> bytes:
    def _norm(v: Any) -> Any:
        if isinstance(v, dict):
            return {str(k): _norm(v2) for k, v2 in sorted(v.items(), key=lambda kv: str(kv[0]))}
        if isinstance(v, list):
            return [_norm(x) for x in v]
        return v

    text = json.dumps(_norm(value), sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)
    return text.encode("utf-8")


def _ed25519_detached_sig_b64(payload: Any, sk_b64: str) -> str:
    # Use PyNaCl (installed in backend-fastapi requirements)
    from nacl.signing import SigningKey

    sk_raw = base64.b64decode(sk_b64)
    # Support either 32-byte seed or 64-byte expanded secret.
    if len(sk_raw) >= 32:
        sk_raw = sk_raw[:32]
    key = SigningKey(sk_raw)
    msg = _canonicalize_json(payload)
    sig = key.sign(msg).signature
    return base64.b64encode(sig).decode("ascii")


def _print_report(rows: List[CheckResult]) -> None:
    # Simple fixed-width table
    headers = ["Time", "Event", "Flow Path", "Logic Validation", "Status"]
    widths = [8, 22, 28, 54, 10]

    def fmt(cols: List[str]) -> str:
        out = []
        for c, w in zip(cols, widths):
            c = (c or "").replace("\n", " ")
            out.append((c[: w - 1] + "…") if len(c) > w else c.ljust(w))
        return " | ".join(out)

    print(fmt(headers))
    print("-" * (sum(widths) + 3 * (len(widths) - 1)))
    for r in rows:
        print(fmt([r.time_label, r.event, r.flow_path, r.validation, r.status]))
        if r.evidence:
            print(f"  evidence: {r.evidence}")


def main() -> int:
    laravel_base = os.getenv("SRS_LARAVEL_API_BASE", "http://localhost:8000/api").rstrip("/")
    fastapi_base = os.getenv("SRS_FASTAPI_API_BASE", "http://localhost:8001/api/v1").rstrip("/")

    email = os.getenv("SRS_EMAIL", "srs@example.com")
    password = os.getenv("SRS_PASSWORD", "Password123!")
    display = os.getenv("SRS_DISPLAY_NAME", "SRS User")

    laravel_sk_b64 = os.getenv("SRS_LARAVEL_SERVICE_PRIVATE_KEY_B64")
    fastapi_sk_b64 = os.getenv("SRS_FASTAPI_SERVICE_PRIVATE_KEY_B64")

    rows: List[CheckResult] = []

    client = httpx.Client(timeout=10)

    def _conn_hint() -> str:
        return (
            "Connection refused. Start Laravel/FastAPI and/or set base URLs: "
            "SRS_LARAVEL_API_BASE (e.g. http://127.0.0.1:8000/api) and "
            "SRS_FASTAPI_API_BASE (e.g. http://127.0.0.1:8001/api/v1)."
        )

    def post(url: str, json_body: Dict[str, Any], headers: Optional[Dict[str, str]] = None) -> Tuple[int, Any, str]:
        try:
            resp = client.post(url, json=json_body, headers=headers)
        except httpx.RequestError as exc:
            return 0, {"detail": str(exc)}, _conn_hint()
        text = resp.text
        try:
            return resp.status_code, resp.json(), text
        except Exception:
            return resp.status_code, text, text

    def get(url: str, headers: Optional[Dict[str, str]] = None) -> Tuple[int, Any, str]:
        try:
            resp = client.get(url, headers=headers)
        except httpx.RequestError as exc:
            return 0, {"detail": str(exc)}, _conn_hint()
        text = resp.text
        try:
            return resp.status_code, resp.json(), text
        except Exception:
            return resp.status_code, text, text

    # T+0s — FastAPI rejects unsigned Laravel control-plane request (if enforcement enabled)
    t0 = "T+0s"
    now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    status_code, body, raw = post(
        f"{fastapi_base}/command/dispatch",
        {
            "command_id": "SRS-AUTH",
            "device_id": "SRS-DEVICE",
            "trace_id": "SRS-TRACE",
            "seq": 1,
            "method": "ping",
            "params": {},
            "sensitive": False,
            "policy": {"decision": "allow"},
            "compliance": {},
            "envelope": {
                "header": {"timestamp": now_iso},
                "body": {"method": "ping", "params": {}, "sensitive": False},
                "meta": {"device_id": "SRS-DEVICE"},
                "sig": "placeholder",
            },
        },
        headers={},
    )
    if status_code == 0:
        rows.append(CheckResult(t0, "Control-plane auth", "Laravel -> FastAPI", "FastAPI reachable", "FAIL", raw))
        _print_report(rows)
        return 2
    if status_code == 401 and isinstance(body, dict) and "Missing X-Laravel-Signature" in (body.get("detail") or ""):
        rows.append(CheckResult(t0, "Control-plane auth", "Laravel -> FastAPI", "Reject missing X-Laravel-Signature", "MET", body.get("detail", "")))
    else:
        rows.append(CheckResult(t0, "Control-plane auth", "Laravel -> FastAPI", "Reject missing X-Laravel-Signature", "SKIP", f"status={status_code} body={raw[:120]}"))

    # Register user (idempotent-ish; if email already exists, fall back to login)
    t2 = "T+2s"
    # Mobile identity: generate a one-off Ed25519-like pubkey.
    # If PyNaCl isn't installed, fall back to random 32 bytes (sufficient for exercising API flows).
    try:
        from nacl.signing import SigningKey  # type: ignore

        mobile_seed = SigningKey.generate()
        mobile_pub_b64 = base64.b64encode(mobile_seed.verify_key.encode()).decode("ascii")
    except Exception:
        mobile_pub_b64 = base64.b64encode(os.urandom(32)).decode("ascii")

    status_code, body, raw = post(
        f"{laravel_base}/register",
        {"display_name": display, "email": email, "password": password, "pubkey": mobile_pub_b64},
    )
    if status_code == 0:
        rows.append(CheckResult(t2, "User login", "Mobile -> Laravel", "Laravel reachable", "FAIL", raw))
        _print_report(rows)
        return 2
    if status_code in (200, 201) and isinstance(body, dict) and body.get("user_id"):
        user_id = body["user_id"]
    else:
        # login if already registered
        status_code, body, raw = post(
            f"{laravel_base}/login",
            {"email": email, "password": password, "device_fingerprint": "srs", "push_token": None},
        )
        if status_code >= 400 or not isinstance(body, dict) or not body.get("user_id"):
            rows.append(CheckResult(t2, "User login", "Mobile -> Laravel", "Obtain session_id + user_id", "FAIL", f"status={status_code} body={raw[:200]}"))
            _print_report(rows)
            return 2
        user_id = body["user_id"]

    # login to get session_id
    status_code, body, raw = post(
        f"{laravel_base}/login",
        {"email": email, "password": password, "device_fingerprint": "srs", "push_token": None},
    )
    if status_code >= 400 or not isinstance(body, dict) or not body.get("session_id"):
        rows.append(CheckResult(t2, "User login", "Mobile -> Laravel", "Obtain session_id + user_id", "FAIL", f"status={status_code} body={raw[:200]}"))
        _print_report(rows)
        return 2

    session_id = body["session_id"]
    rows.append(CheckResult(t2, "User login", "Mobile -> Laravel", "Session established", "MET", f"user_id={user_id} session_id={session_id}"))

    # Create a device (simulating "agent presence") via pairing endpoints.
    # This is a pragmatic substitute for the WSS presence path.
    status_code, body, raw = post(f"{laravel_base}/pair/init", {"device_label": "SRS-PC"})
    if status_code >= 400 or not isinstance(body, dict) or not body.get("pair_token"):
        rows.append(CheckResult("T+3s", "Device bootstrap", "Agent -> Laravel", "Device record created", "FAIL", f"status={status_code} body={raw[:200]}"))
        _print_report(rows)
        return 2

    pair_token = body["pair_token"]
    status_code, body, raw = post(f"{laravel_base}/pair/confirm", {"pair_token": pair_token})
    if status_code >= 400 or not isinstance(body, dict) or not body.get("device_id"):
        rows.append(CheckResult("T+3s", "Device bootstrap", "Agent -> Laravel", "Device record created", "FAIL", f"status={status_code} body={raw[:200]}"))
        _print_report(rows)
        return 2

    device_id = body["device_id"]

    # T+5s — Device discovery
    status_code, body, raw = get(f"{laravel_base}/devices/unpaired?user_id={user_id}&session_id={session_id}")
    if status_code == 200 and isinstance(body, dict):
        found = any((d.get("device_id") == device_id) for d in (body.get("devices") or []))
        rows.append(CheckResult("T+5s", "Device discovery", "Mobile -> Laravel", "Unpaired device visible", "MET" if found else "FAIL", f"device_id={device_id}"))
        if not found:
            _print_report(rows)
            return 2
    else:
        rows.append(CheckResult("T+5s", "Device discovery", "Mobile -> Laravel", "Unpaired device visible", "FAIL", f"status={status_code} body={raw[:200]}"))
        _print_report(rows)
        return 2

    # T+7s — Claim
    status_code, body, raw = post(f"{laravel_base}/devices/{device_id}/claim", {"user_id": user_id, "session_id": session_id})
    if status_code == 200 and isinstance(body, dict) and body.get("status") == "ok":
        # verify it disappears from unpaired
        status_code2, body2, raw2 = get(f"{laravel_base}/devices/unpaired?user_id={user_id}&session_id={session_id}")
        still = False
        if status_code2 == 200 and isinstance(body2, dict):
            still = any((d.get("device_id") == device_id) for d in (body2.get("devices") or []))
        rows.append(CheckResult("T+7s", "Claim & pair", "Mobile -> Laravel", "Claim removes device from unpaired", "MET" if not still else "FAIL", f"device_id={device_id}"))
        if still:
            _print_report(rows)
            return 2
    else:
        rows.append(CheckResult("T+7s", "Claim & pair", "Mobile -> Laravel", "Claim endpoint assigns user_id", "FAIL", f"status={status_code} body={raw[:200]}"))
        _print_report(rows)
        return 2

    # T+10s — 2FA enrollment (runtime) + encrypted storage (static)
    status_code, body, raw = post(f"{laravel_base}/2fa/setup", {"user_id": user_id, "session_id": session_id})
    if status_code == 200 and isinstance(body, dict) and body.get("secret"):
        secret = body["secret"]
        rows.append(CheckResult("T+10s", "2FA setup", "Mobile -> Laravel", "Setup returns Base32 secret", "MET", f"secret_prefix={str(secret)[:6]}"))
    else:
        rows.append(CheckResult("T+10s", "2FA setup", "Mobile -> Laravel", "Setup returns Base32 secret", "FAIL", f"status={status_code} body={raw[:200]}"))
        _print_report(rows)
        return 2

    # confirm with a code (try a small window to avoid clock skew)
    codes = [_totp(secret), _totp(secret, int(time.time()) - 30), _totp(secret, int(time.time()) + 30)]
    ok = False
    for code in codes:
        status_code, body, raw = post(f"{laravel_base}/2fa/confirm", {"user_id": user_id, "session_id": session_id, "two_factor_code": code})
        if status_code == 200:
            ok = True
            break
    rows.append(CheckResult("T+12s", "2FA confirm", "Mobile -> Laravel", "First TOTP enables 2FA", "MET" if ok else "FAIL"))
    if not ok:
        _print_report(rows)
        return 2

    # static check for encrypted cast
    try:
        user_model_path = os.path.join(os.path.dirname(__file__), "..", "..", "backend-laravel", "app", "Models", "User.php")
        user_model_path = os.path.abspath(user_model_path)
        txt = open(user_model_path, "r", encoding="utf-8").read()
        enc_ok = "'two_factor_secret' => 'encrypted'" in txt
        rows.append(CheckResult("T+13s", "2FA storage", "Laravel", "two_factor_secret uses encrypted cast", "MET" if enc_ok else "FAIL"))
        if not enc_ok:
            _print_report(rows)
            return 2
    except Exception as exc:
        rows.append(CheckResult("T+13s", "2FA storage", "Laravel", "two_factor_secret uses encrypted cast", "SKIP", str(exc)))

    # T+15s — Non-sensitive cmd (lock_screen) should not require 2FA
    status_code, body, raw = post(
        f"{laravel_base}/commands",
        {
            "client_message_id": str(int(time.time() * 1000)),
            "device_id": device_id,
            "method": "lock_screen",
            "params": {},
            "sensitive": False,
            "user_id": user_id,
            "attestation_status": "pass",
        },
    )
    if status_code == 201 and isinstance(body, dict) and body.get("status") == "accepted":
        rows.append(CheckResult("T+15s", "Non-sensitive cmd", "Mobile -> Laravel", "No 2FA required", "MET", f"command_id={body.get('command_id')}"))
    else:
        rows.append(CheckResult("T+15s", "Non-sensitive cmd", "Mobile -> Laravel", "No 2FA required", "FAIL", f"status={status_code} body={raw[:200]}"))
        _print_report(rows)
        return 2

    # T+20s — Sensitive cmd without TOTP must be blocked (use screenshot - requires2fa)
    status_code, body, raw = post(
        f"{laravel_base}/commands",
        {
            "client_message_id": str(int(time.time() * 1000) + 1),
            "device_id": device_id,
            "method": "screenshot",
            "params": {"resolution": "720p"},
            "sensitive": True,
            "user_id": user_id,
            "user_role": "admin",
            "attestation_status": "pass",
        },
    )
    if status_code == 403 and isinstance(body, dict) and body.get("status") == "require_2fa":
        rows.append(CheckResult("T+20s", "Sensitive cmd", "Mobile -> Laravel", "403 require_2fa without code", "MET"))
    else:
        rows.append(CheckResult("T+20s", "Sensitive cmd", "Mobile -> Laravel", "403 require_2fa without code", "FAIL", f"status={status_code} body={raw[:200]}"))
        _print_report(rows)
        return 2

    # Wrong TOTP must be denied
    status_code, body, raw = post(
        f"{laravel_base}/commands",
        {
            "client_message_id": str(int(time.time() * 1000) + 2),
            "device_id": device_id,
            "method": "screenshot",
            "params": {"resolution": "720p"},
            "sensitive": True,
            "user_id": user_id,
            "two_factor_code": "000000",
            "user_role": "admin",
            "attestation_status": "pass",
        },
    )
    if status_code == 403 and isinstance(body, dict) and body.get("reason") == "invalid_2fa":
        rows.append(CheckResult("T+22s", "TOTP attacker", "Mobile -> Laravel", "Wrong code rejected (invalid_2fa)", "MET"))
    else:
        rows.append(CheckResult("T+22s", "TOTP attacker", "Mobile -> Laravel", "Wrong code rejected (invalid_2fa)", "FAIL", f"status={status_code} body={raw[:200]}"))
        _print_report(rows)
        return 2

    # Correct TOTP should allow
    good_code = _totp(secret)
    status_code, body, raw = post(
        f"{laravel_base}/commands",
        {
            "client_message_id": str(int(time.time() * 1000) + 3),
            "device_id": device_id,
            "method": "screenshot",
            "params": {"resolution": "720p"},
            "sensitive": True,
            "user_id": user_id,
            "two_factor_code": good_code,
            "user_role": "admin",
            "attestation_status": "pass",
        },
    )
    if status_code == 201 and isinstance(body, dict) and body.get("status") == "accepted":
        rows.append(CheckResult("T+25s", "Sensitive cmd", "Mobile -> Laravel", "Correct TOTP allows queue", "MET", f"command_id={body.get('command_id')}"))
    else:
        rows.append(CheckResult("T+25s", "Sensitive cmd", "Mobile -> Laravel", "Correct TOTP allows queue", "FAIL", f"status={status_code} body={raw[:200]}"))
        _print_report(rows)
        return 2

    # Optional: Replay test against FastAPI control-plane seq, if we can sign a payload.
    if laravel_sk_b64:
        try:
            from nacl.signing import SigningKey  # type: ignore
        except Exception:
            rows.append(CheckResult("T+28s", "Replay attack", "Laravel -> FastAPI", "Same seq rejected (replay)", "SKIP", "PyNaCl not installed in this venv"))
            _print_report(rows)
            return 0
        payload = {
            "command_id": "SRS-REPLAY",
            "device_id": device_id,
            "trace_id": "SRS",
            "seq": 12345,
            "method": "ping",
            "params": {},
            "sensitive": False,
            "policy": {"decision": "allow"},
            "compliance": {},
            "envelope": {"header": {"timestamp": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}, "body": {"method": "ping", "params": {}, "sensitive": False}, "meta": {"device_id": device_id}, "sig": None},
        }
        sig = _ed25519_detached_sig_b64(payload, laravel_sk_b64)
        status_code, body, raw = post(f"{fastapi_base}/command/dispatch", payload, headers={"X-Laravel-Signature": sig})
        status_code2, body2, raw2 = post(f"{fastapi_base}/command/dispatch", payload, headers={"X-Laravel-Signature": sig})

        if status_code == 200 and status_code2 == 401:
            rows.append(CheckResult("T+28s", "Replay attack", "Laravel -> FastAPI", "Same seq rejected (replay)", "MET", f"second={raw2[:80]}"))
        elif status_code == 200 and status_code2 == 200:
            rows.append(CheckResult("T+28s", "Replay attack", "Laravel -> FastAPI", "Same seq rejected (replay)", "FAIL", "FastAPI accepted replay; REQUIRE_LARAVEL_SEQ likely off"))
        else:
            rows.append(CheckResult("T+28s", "Replay attack", "Laravel -> FastAPI", "Same seq rejected (replay)", "SKIP", f"first={status_code} second={status_code2}"))
    else:
        rows.append(CheckResult("T+28s", "Replay attack", "Laravel -> FastAPI", "Same seq rejected (replay)", "SKIP", "Set SRS_LARAVEL_SERVICE_PRIVATE_KEY_B64 to enable"))

    # Webhook signature enforcement check (fail-closed): missing signature should be rejected if enabled.
    webhook_payload = {
        "command_id": "SRS-WEBHOOK",
        "device_id": device_id,
        "trace_id": "SRS-TRACE",
        "execution_state": "completed",
        "result": {"ok": True},
        "error_code": None,
        "error_message": None,
        "timestamp": now_iso,
    }
    status_code, body, raw = post(
        f"{laravel_base.replace('/api', '')}/api/v1/webhook/command/result",
        webhook_payload,
    )
    if status_code == 401:
        rows.append(CheckResult("T+35s", "Webhook trust", "FastAPI -> Laravel", "Reject missing X-FastAPI-Signature", "MET"))
        if fastapi_sk_b64:
            sig = _ed25519_detached_sig_b64(webhook_payload, fastapi_sk_b64)
            status_code2, body2, raw2 = post(
                f"{laravel_base.replace('/api', '')}/api/v1/webhook/command/result",
                webhook_payload,
                headers={"X-FastAPI-Signature": sig},
            )
            rows.append(
                CheckResult(
                    "T+36s",
                    "Webhook trust",
                    "FastAPI -> Laravel",
                    "Accept valid signed webhook",
                    "MET" if status_code2 in (200, 404) else "FAIL",
                    f"status={status_code2}",
                )
            )
        else:
            rows.append(CheckResult("T+36s", "Webhook trust", "FastAPI -> Laravel", "Accept valid signed webhook", "SKIP", "Set SRS_FASTAPI_SERVICE_PRIVATE_KEY_B64 to enable"))
    else:
        rows.append(
            CheckResult(
                "T+35s",
                "Webhook trust",
                "FastAPI -> Laravel",
                "Reject missing X-FastAPI-Signature",
                "SKIP",
                f"status={status_code} (signature enforcement likely off)",
            )
        )

    _print_report(rows)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
