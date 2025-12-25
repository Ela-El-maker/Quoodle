from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import os
import time
from datetime import datetime, timezone
from typing import Any, Dict, Optional, Tuple

import httpx


def log(event: str, context: str = "", logic: str = "", result: str = "") -> None:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    print(f"[SYSTEM-TRACE] [{ts}] EVENT: {event}")
    if context:
        print(f"[SYSTEM-TRACE] [CONTEXT] {context}")
    if logic:
        print(f"[SYSTEM-TRACE] [LOGIC] {logic}")
    if result:
        print(f"[SYSTEM-TRACE] [RESULT] {result}")
    print("-" * 70)


def _b32decode_no_pad(s: str) -> bytes:
    s = s.strip().replace(" ", "").upper()
    pad = (8 - (len(s) % 8)) % 8
    s = s + ("=" * pad)
    return base64.b32decode(s, casefold=True)


def totp(secret_b32: str, unix_time: Optional[int] = None, period: int = 30, digits: int = 6) -> str:
    now = int(unix_time if unix_time is not None else time.time())
    counter = now // period
    key = _b32decode_no_pad(secret_b32)
    msg = counter.to_bytes(8, "big")
    digest = hmac.new(key, msg, hashlib.sha1).digest()
    off = digest[-1] & 0x0F
    code_int = int.from_bytes(digest[off : off + 4], "big") & 0x7FFFFFFF
    return str(code_int % (10**digits)).zfill(digits)


def canonicalize_json(value: Any) -> bytes:
    def _norm(v: Any) -> Any:
        if isinstance(v, dict):
            return {str(k): _norm(v2) for k, v2 in sorted(v.items(), key=lambda kv: str(kv[0]))}
        if isinstance(v, list):
            return [_norm(x) for x in v]
        return v

    text = json.dumps(_norm(value), sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)
    return text.encode("utf-8")


def ed25519_sig_b64(payload: Any, sk_b64: str) -> str:
    from nacl.signing import SigningKey

    raw = base64.b64decode(sk_b64)
    raw = raw[:32] if len(raw) >= 32 else raw
    key = SigningKey(raw)
    sig = key.sign(canonicalize_json(payload)).signature
    return base64.b64encode(sig).decode("ascii")


async def ws_unpaired_probe(fastapi_ws_url: str, device_id: str) -> bool:
    """Send a minimally-formed AUTH envelope with an empty signature.

    This should be rejected (fail-closed) but still cause FastAPI to report the device as unpaired to Laravel.
    """
    try:
        import websockets  # type: ignore
    except Exception:
        log(
            "DISCOVERY_WS_SKIPPED",
            context=f"FastAPI WS={fastapi_ws_url}",
            logic="websockets package not installed",
            result="SKIP (pip install websockets)",
        )
        return False

    payload = {
        "type": "AUTH",
        "from": "agent",
        "device_id": device_id,
        "message_id": "m-auth-0",
        "session_id": None,
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "body": {
            "auth": {"jwt": "invalid", "nonce": "nonce-0"},
            "agent_info": {"agent_version": "srs", "os_build": "srs"},
        },
        "sig": "",
    }

    try:
        async with websockets.connect(fastapi_ws_url) as ws:
            await ws.send(json.dumps(payload))
            # Expect close or error.
            try:
                await ws.recv()
            except Exception:
                pass
    except Exception:
        # Even if it fails to connect, we can't validate this hop.
        return False

    return True


def main() -> int:
    laravel_base = os.getenv("SRS_LARAVEL_API_BASE", "http://localhost:8000/api").rstrip("/")
    fastapi_api = os.getenv("SRS_FASTAPI_API_BASE", "http://localhost:8001/api/v1").rstrip("/")
    fastapi_ws = os.getenv("SRS_FASTAPI_WS", "ws://localhost:8001/agent")

    email = os.getenv("SRS_EMAIL", "trace@example.com")
    password = os.getenv("SRS_PASSWORD", "Password123!")
    display = os.getenv("SRS_DISPLAY_NAME", "TRACE User")

    # For signed webhook tests
    fastapi_sk_b64 = os.getenv("SRS_FASTAPI_SERVICE_PRIVATE_KEY_B64")

    verify_delay = int(os.getenv("STATE_VERIFY_DELAY_SECONDS", "10"))
    audit_archive_path = os.getenv("AUDIT_ARCHIVE_PATH", os.path.join("backend-laravel", "storage", "app", "audit_archive.jsonl"))

    client = httpx.Client(timeout=10)

    def _conn_hint() -> str:
        return (
            "Connection refused. Ensure services are running and the base URLs are correct. "
            "Set SRS_LARAVEL_API_BASE (e.g. http://127.0.0.1:8000/api) and SRS_FASTAPI_API_BASE "
            "(e.g. http://127.0.0.1:8001/api/v1)."
        )

    def post(url: str, body: Dict[str, Any], headers: Optional[Dict[str, str]] = None) -> Tuple[int, Any, str]:
        try:
            r = client.post(url, json=body, headers=headers)
        except httpx.RequestError as exc:
            return 0, {"detail": str(exc)}, _conn_hint()
        raw = r.text
        try:
            return r.status_code, r.json(), raw
        except Exception:
            return r.status_code, raw, raw

    def get(url: str, headers: Optional[Dict[str, str]] = None) -> Tuple[int, Any, str]:
        try:
            r = client.get(url, headers=headers)
        except httpx.RequestError as exc:
            return 0, {"detail": str(exc)}, _conn_hint()
        raw = r.text
        try:
            return r.status_code, r.json(), raw
        except Exception:
            return r.status_code, raw, raw

    # Quick connectivity probes (fail early with guidance).
    try:
        probe = client.get(fastapi_api.replace('/api/v1', '') + "/health")
        if probe.status_code >= 500:
            log("FASTAPI_HEALTH", context=fastapi_api, logic="GET /health", result=f"WARN: {probe.status_code}")
    except Exception:
        log("FASTAPI_HEALTH", context=fastapi_api, logic="GET /health", result="SKIP")

    # 0. Discovery: FastAPI rejects unsigned/unknown AUTH but reports as unpaired.
    device_id = f"SRS-PC-{int(time.time())}"
    log(
        "DISCOVERY_WS_AUTH",
        context=f"Device: {device_id}",
        logic="Agent sends AUTH without valid signature/key; FastAPI should fail-closed but surface device as pending_pairing",
        result="ATTEMPT",
    )
    try:
        asyncio.run(ws_unpaired_probe(fastapi_ws, device_id))
    except Exception:
        pass

    # Wait briefly for webhook propagation.
    time.sleep(1.0)

    # 1. Identity: Register/login (mobile keypair generation is local; here we just send a pubkey)
    try:
        from nacl.signing import SigningKey  # type: ignore

        pub_b64 = base64.b64encode(SigningKey.generate().verify_key.encode()).decode("ascii")
    except Exception:
        pub_b64 = base64.b64encode(os.urandom(32)).decode("ascii")

    status, body, raw = post(f"{laravel_base}/register", {"display_name": display, "email": email, "password": password, "pubkey": pub_b64})
    if status == 0:
        log(
            "LARAVEL_CONNECT",
            context=f"Base: {laravel_base}",
            logic="POST /register",
            result=f"FAIL: {raw}",
        )
        return 2
    if status not in (200, 201):
        log("IDENTITY_REGISTER", context=f"Email: {email}", logic="Register user", result=f"Non-fatal (likely exists): {status}")

    status, body, raw = post(f"{laravel_base}/login", {"email": email, "password": password, "device_fingerprint": "trace"})
    if status == 0:
        log(
            "LARAVEL_CONNECT",
            context=f"Base: {laravel_base}",
            logic="POST /login",
            result=f"FAIL: {raw}",
        )
        return 2
    if status >= 400 or not isinstance(body, dict) or not body.get("user_id"):
        log("IDENTITY_LOGIN", context=f"Email: {email}", logic="Login user", result=f"FAIL: {status} {raw[:120]}")
        return 2

    user_id = body["user_id"]
    session_id = body["session_id"]
    log("IDENTITY_LOGIN", context=f"User: {user_id} | Session: {session_id}", logic="Session established", result="SUCCESS")

    # 2. Claim: device should be visible as unpaired, then claim it.
    status, body, raw = get(f"{laravel_base}/devices/unpaired?user_id={user_id}&session_id={session_id}")
    if status != 200 or not isinstance(body, dict):
        log("DISCOVERY_HTTP", context=f"User: {user_id}", logic="Fetch unpaired devices", result=f"FAIL: {status} {raw[:120]}")
        return 2

    found = any((d.get("device_id") == device_id) for d in (body.get("devices") or []))
    log("DISCOVERY_HTTP", context=f"User: {user_id} | Device: {device_id}", logic="Unpaired list contains device", result="SUCCESS" if found else "FAIL")
    if not found:
        return 2

    status, body, raw = post(f"{laravel_base}/devices/{device_id}/claim", {"user_id": user_id, "session_id": session_id})
    if status != 200:
        log("CLAIM", context=f"User: {user_id} | Device: {device_id}", logic="Claim device", result=f"FAIL: {status} {raw[:120]}")
        return 2
    log("CLAIM", context=f"User: {user_id} | Device: {device_id}", logic="devices.user_id set", result="SUCCESS")

    # 3. Enrollment: 2FA setup/confirm
    status, body, raw = post(f"{laravel_base}/2fa/setup", {"user_id": user_id, "session_id": session_id})
    if status != 200 or not isinstance(body, dict) or not body.get("secret"):
        log("2FA_SETUP", context=f"User: {user_id}", logic="Get secret", result=f"FAIL: {status} {raw[:120]}")
        return 2
    secret = body["secret"]

    ok = False
    for code in [totp(secret), totp(secret, int(time.time()) - 30), totp(secret, int(time.time()) + 30)]:
        s2, b2, r2 = post(f"{laravel_base}/2fa/confirm", {"user_id": user_id, "session_id": session_id, "two_factor_code": code})
        if s2 == 200:
            ok = True
            break
    log("2FA_CONFIRM", context=f"User: {user_id}", logic="Confirm 2FA", result="SUCCESS" if ok else "FAIL")
    if not ok:
        return 2

    # 4. Normal op: lock_screen should not require 2FA
    status, body, raw = post(
        f"{laravel_base}/commands",
        {"client_message_id": str(int(time.time() * 1000)), "device_id": device_id, "method": "lock_screen", "params": {}, "sensitive": False, "user_id": user_id, "attestation_status": "pass"},
    )
    log(
        "NON_SENSITIVE_COMMAND",
        context=f"User: {user_id} | Device: {device_id} | Method: lock_screen",
        logic="Low risk command should bypass 2FA",
        result="SUCCESS" if status == 201 else f"FAIL: {status}",
    )

    # 5. Attack sim: sensitive command without TOTP must require_2fa
    status, body, raw = post(
        f"{laravel_base}/commands",
        {"client_message_id": str(int(time.time() * 1000) + 1), "device_id": device_id, "method": "screenshot", "params": {"resolution": "720p"}, "sensitive": True, "user_id": user_id, "user_role": "admin", "attestation_status": "pass"},
    )
    enforced = status == 403 and isinstance(body, dict) and body.get("status") == "require_2fa"
    log(
        "ATTACK_NO_2FA",
        context=f"User: {user_id} | Device: {device_id} | Method: screenshot",
        logic="Sensitive op must be blocked without TOTP",
        result="SUCCESS" if enforced else f"FAIL: {status} {raw[:120]}",
    )
    if not enforced:
        return 2

    # 6. Hardened op: sensitive command with correct 2FA
    good = totp(secret)
    status, body, raw = post(
        f"{laravel_base}/commands",
        {"client_message_id": str(int(time.time() * 1000) + 2), "device_id": device_id, "method": "screenshot", "params": {"resolution": "720p"}, "sensitive": True, "user_id": user_id, "user_role": "admin", "two_factor_code": good, "attestation_status": "pass"},
    )
    if status != 201 or not isinstance(body, dict) or not body.get("command_id"):
        log("SENSITIVE_COMMAND", context=f"Device: {device_id}", logic="Correct TOTP queues command", result=f"FAIL: {status} {raw[:120]}")
        return 2
    command_id = body["command_id"]
    log("SENSITIVE_COMMAND", context=f"Command: {command_id}", logic="Queued and verification scheduled", result="SUCCESS")

    # Evidence archive (best-effort): if queue+dispatch ran, the envelope should be appended.
    try:
        p = audit_archive_path
        if not os.path.isabs(p):
            repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
            p = os.path.join(repo_root, p)

        if os.path.exists(p):
            txt = open(p, "r", encoding="utf-8").read()
            found = command_id in txt
            log(
                "EVIDENCE_ARCHIVE",
                context=f"Archive: {p}",
                logic="Signed envelope archived (append-only JSONL)",
                result="SUCCESS" if found else "SKIP (dispatch/worker may not have run yet)",
            )
        else:
            log(
                "EVIDENCE_ARCHIVE",
                context=f"Archive: {p}",
                logic="Signed envelope archived (append-only JSONL)",
                result="SKIP (archive not created yet)",
            )
    except Exception as exc:
        log(
            "EVIDENCE_ARCHIVE",
            context="",
            logic="Signed envelope archived (append-only JSONL)",
            result=f"SKIP ({exc})",
        )

    # Policy hash anchor + drift detection: send telemetry with wrong policy_hash after delay.
    log(
        "GROUND_TRUTH_WAIT",
        context=f"Waiting {verify_delay}s",
        logic="Allow verifier not_before window to pass",
        result="WAIT",
    )
    time.sleep(max(verify_delay + 1, 2))

    telemetry_payload = {
        "device_id": device_id,
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "rollup": {
            "avg_cpu": 1.0,
            "avg_ram": 1.0,
            "avg_disk": 1.0,
            "avg_tx": 0.0,
            "avg_rx": 0.0,
            "risk_score_avg": 0.0,
            "policy_hash": "BAD_POLICY_HASH",
        },
    }

    headers = None
    if fastapi_sk_b64:
        try:
            sig = ed25519_sig_b64(telemetry_payload, fastapi_sk_b64)
            headers = {"X-FastAPI-Signature": sig}
        except Exception:
            headers = None

    # Webhook base is Laravel app base, not /api
    webhook_url = f"{laravel_base.replace('/api', '')}/api/v1/webhook/telemetry/summary"
    status, body, raw = post(webhook_url, telemetry_payload, headers=headers)

    if status == 401 and not headers:
        log(
            "TELEMETRY_WEBHOOK",
            context=f"Device: {device_id}",
            logic="Webhook signature required; provide SRS_FASTAPI_SERVICE_PRIVATE_KEY_B64 and ensure PyNaCl installed",
            result="SKIP",
        )
        return 0

    log(
        "TELEMETRY_WEBHOOK",
        context=f"Device: {device_id}",
        logic="Ingest telemetry with policy_hash anchor",
        result="SUCCESS" if status == 200 else f"FAIL: {status} {raw[:120]}",
    )

    # Verify policy out-of-sync surfaced
    status, body, raw = get(f"{laravel_base}/devices/{device_id}")
    pin = isinstance(body, dict) and body.get("policy_in_sync") is False
    log(
        "POLICY_HASH_ANCHOR",
        context=f"Device: {device_id}",
        logic="Device shows policy_in_sync=false when reported_policy_hash mismatches",
        result="SUCCESS" if pin else f"FAIL: {status} {raw[:120]}",
    )

    # Verify drift detection alert
    status, body, raw = get(f"{laravel_base}/alerts?severity=high")
    found_alert = False
    if status == 200 and isinstance(body, dict):
        for a in body.get("alerts") or []:
            if a.get("device_id") == device_id and command_id in (a.get("message") or ""):
                found_alert = True
                break

    log(
        "DRIFT_DETECTION",
        context=f"Device: {device_id} | Command: {command_id}",
        logic="High severity alert raised if telemetry doesn't match expected policy_hash",
        result="SUCCESS" if found_alert else f"FAIL: no alert found (status={status})",
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
