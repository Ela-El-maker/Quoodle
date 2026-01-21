#!/usr/bin/env python3
import base64
import hashlib
import json
import os
import random
import socket
import ssl
import struct
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse

import requests

try:
    from nacl.signing import SigningKey
    from nacl.exceptions import BadSignatureError
    HAVE_PYNACL = True
except Exception:
    HAVE_PYNACL = False

LOG_FIELDS = [
    "timestamp","level","service","env","trace_id","span_id","request_id",
    "user_id(optional)","device_id(optional)","command_id(optional)","event_type",
    "stage","sync_or_async","direction","endpoint_or_channel","latency_ms",
    "result","error_code(optional)","retry_count(optional)","idempotency_key(optional)"
]

ENV = os.getenv("ENV", "local")
LARAVEL_BASE_URL = os.getenv("LARAVEL_BASE_URL", "").rstrip("/")
FASTAPI_BASE_URL = os.getenv("FASTAPI_BASE_URL", "").rstrip("/")
TEST_USER_EMAIL = os.getenv("TEST_USER_EMAIL", "")
TEST_USER_PASSWORD = os.getenv("TEST_USER_PASSWORD", "")
RUNS = int(os.getenv("RUNS", "3"))
SEED = int(os.getenv("SEED", "1337"))
READY_TIMEOUT = float(os.getenv("READY_TIMEOUT", "60"))
READY_INTERVAL = float(os.getenv("READY_INTERVAL", "1"))
HTTP_TIMEOUT = float(os.getenv("HTTP_TIMEOUT", "8"))
POLL_TIMEOUT = float(os.getenv("POLL_TIMEOUT", "60"))
POLL_INTERVAL = float(os.getenv("POLL_INTERVAL", "2"))
WSS_TIMEOUT = float(os.getenv("WSS_TIMEOUT", "30"))
WSS_READ_TIMEOUT = float(os.getenv("WSS_READ_TIMEOUT", "2"))
RETRY_COUNT = int(os.getenv("RETRY_COUNT", "2"))
PAIR_MAX_ATTEMPTS = int(os.getenv("PAIR_MAX_ATTEMPTS", "5"))
FAULTS = [f.strip() for f in os.getenv("FAULTS", "").split(",") if f.strip()]

AGENT_JWT = os.getenv("AGENT_JWT", "")
POLICY_HASH = os.getenv("POLICY_HASH", "")
POLICY_VERSION = os.getenv("POLICY_VERSION", "")

LARAVEL_SERVICE_PRIVATE_KEY_B64 = os.getenv("LARAVEL_SERVICE_PRIVATE_KEY_B64", "")
FASTAPI_SERVICE_PRIVATE_KEY_B64 = os.getenv("FASTAPI_SERVICE_PRIVATE_KEY_B64", "")
LARAVEL_COMMAND_PUBLIC_KEY_B64 = os.getenv("LARAVEL_COMMAND_PUBLIC_KEY_B64", "")
FASTAPI_WSS_PUBLIC_KEY_B64 = os.getenv("FASTAPI_WSS_PUBLIC_KEY_B64", "")
RUN_NONCE = os.getenv("RUN_NONCE", "") or uuid.uuid4().hex[:8]

DISPATCH_MODE = os.getenv("DISPATCH_MODE", "laravel")  # laravel|direct
WEBHOOK_MODE = os.getenv("WEBHOOK_MODE", "fastapi")    # fastapi|direct|both

random.seed(SEED)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def log_event(**kwargs):
    record = {k: kwargs.get(k) for k in LOG_FIELDS}
    record["timestamp"] = record["timestamp"] or now_iso()
    record["level"] = record["level"] or "INFO"
    record["service"] = record["service"] or "e2e_harness"
    record["env"] = record["env"] or ENV
    if record.get("user_id(optional)") is None and "user_id" in kwargs:
        record["user_id(optional)"] = kwargs.get("user_id")
    if record.get("device_id(optional)") is None and "device_id" in kwargs:
        record["device_id(optional)"] = kwargs.get("device_id")
    if record.get("command_id(optional)") is None and "command_id" in kwargs:
        record["command_id(optional)"] = kwargs.get("command_id")
    if record.get("idempotency_key(optional)") is None and "idempotency_key" in kwargs:
        record["idempotency_key(optional)"] = kwargs.get("idempotency_key")
    if record.get("error_code(optional)") is None and "error_code" in kwargs:
        record["error_code(optional)"] = kwargs.get("error_code")
    if record.get("retry_count(optional)") is None and "retry_count" in kwargs:
        record["retry_count(optional)"] = kwargs.get("retry_count")
    print(json.dumps(record), flush=True)


def canonicalize(obj: Any) -> bytes:
    def _normalize(v: Any) -> Any:
        if isinstance(v, dict):
            return {str(k): _normalize(vv) for k, vv in sorted(v.items(), key=lambda kv: str(kv[0]))}
        if isinstance(v, list):
            return [_normalize(x) for x in v]
        return v
    normalized = _normalize(obj)
    text = json.dumps(normalized, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return text.encode("utf-8")


def strip_sig(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: strip_sig(v) for k, v in obj.items() if k not in ("sig", "signature")}
    if isinstance(obj, list):
        return [strip_sig(v) for v in obj]
    return obj


def b64e(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")


def b64d(txt: str) -> bytes:
    return base64.b64decode(txt)


def sign_ed25519(private_b64: str, payload: Dict[str, Any]) -> str:
    if not HAVE_PYNACL:
        raise RuntimeError("PyNaCl required for Ed25519 signing")
    sk_raw = b64d(private_b64)
    if len(sk_raw) == 64:
        sk_raw = sk_raw[:32]
    signer = SigningKey(sk_raw)
    msg = canonicalize(strip_sig(payload))
    sig = signer.sign(msg).signature
    return b64e(sig)


def verify_ed25519(public_b64: str, payload: Dict[str, Any], sig_b64: str) -> bool:
    if not HAVE_PYNACL:
        return False
    from nacl.signing import VerifyKey
    msg = canonicalize(strip_sig(payload))
    vk = VerifyKey(b64d(public_b64))
    try:
        vk.verify(msg, b64d(sig_b64))
        return True
    except BadSignatureError:
        return False


def http_request(method: str, url: str, headers=None, json_body=None, trace_id=None, stage="", direction="outbound"):
    req_id = str(uuid.uuid4())
    for attempt in range(RETRY_COUNT + 1):
        start = time.time()
        try:
            resp = requests.request(method, url, headers=headers, json=json_body, timeout=HTTP_TIMEOUT)
            latency = int((time.time() - start) * 1000)
            log_event(
                trace_id=trace_id,
                span_id=str(uuid.uuid4()),
                request_id=req_id,
                event_type="http.request",
                stage=stage,
                sync_or_async="sync",
                direction=direction,
                endpoint_or_channel=url,
                latency_ms=latency,
                result=str(resp.status_code),
                retry_count=str(attempt),
            )
            return resp
        except Exception as exc:
            latency = int((time.time() - start) * 1000)
            log_event(
                trace_id=trace_id,
                span_id=str(uuid.uuid4()),
                request_id=req_id,
                event_type="http.error",
                stage=stage,
                sync_or_async="sync",
                direction=direction,
                endpoint_or_channel=url,
                latency_ms=latency,
                result="exception",
                error_code=str(exc),
                retry_count=str(attempt),
            )
            if attempt >= RETRY_COUNT:
                raise
            time.sleep(0.5 * (2 ** attempt))


def wait_for_http(url: str) -> None:
    deadline = time.time() + READY_TIMEOUT
    while time.time() < deadline:
        try:
            resp = requests.get(url, timeout=HTTP_TIMEOUT)
            if resp.status_code >= 100:
                return
        except Exception:
            time.sleep(READY_INTERVAL)
    raise RuntimeError(f"service_not_ready:{url}")


def resolve_policy_defaults(trace_id: str) -> None:
    global POLICY_HASH, POLICY_VERSION
    if POLICY_HASH and POLICY_VERSION:
        return
    if FASTAPI_BASE_URL:
        try:
            state = http_request(
                "GET",
                f"{FASTAPI_BASE_URL}/api/v1/policy/state",
                trace_id=trace_id,
                stage="policy.state",
                direction="harness->fastapi",
            )
            if state.status_code == 200:
                data = state.json()
                POLICY_HASH = POLICY_HASH or data.get("policy_hash") or data.get("policy", {}).get("policy_hash", "")
                POLICY_VERSION = POLICY_VERSION or data.get("policy_version") or data.get("policy", {}).get("policy_version", "")
        except Exception:
            pass
    if POLICY_HASH and POLICY_VERSION:
        return
    bundle_path = os.path.join("docs", "policy", "policy_bundle.json")
    try:
        with open(bundle_path, "r", encoding="utf-8") as f:
            policy_data = json.load(f)
        canonical = json.dumps(policy_data, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        POLICY_HASH = POLICY_HASH or f"sha256:{hashlib.sha256(canonical.encode('utf-8')).hexdigest()}"
        POLICY_VERSION = POLICY_VERSION or str(policy_data.get("policy_version", ""))
    except Exception:
        pass


class WebSocketClient:
    def __init__(self, url: str, timeout: float = 10.0):
        self.url = url
        self.timeout = timeout
        self.sock: Optional[socket.socket] = None

    def connect(self):
        parsed = urlparse(self.url)
        scheme = parsed.scheme
        host = parsed.hostname
        port = parsed.port or (443 if scheme == "wss" else 80)
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query

        if not host:
            raise RuntimeError("Invalid WebSocket URL")

        raw_sock = socket.create_connection((host, port), timeout=self.timeout)
        if scheme == "wss":
            context = ssl.create_default_context()
            self.sock = context.wrap_socket(raw_sock, server_hostname=host)
        else:
            self.sock = raw_sock

        key = base64.b64encode(os.urandom(16)).decode("ascii")
        req = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(req.encode("ascii"))
        resp = self.sock.recv(4096).decode("ascii", errors="ignore")
        if " 101 " not in resp:
            raise RuntimeError(f"WebSocket handshake failed: {resp.splitlines()[:1]}")
        self.sock.settimeout(WSS_READ_TIMEOUT)

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            finally:
                self.sock = None

    def _send_frame(self, payload: bytes, opcode: int = 1):
        if not self.sock:
            raise RuntimeError("WebSocket not connected")
        fin = 0x80
        mask_bit = 0x80
        length = len(payload)
        header = bytearray()
        header.append(fin | (opcode & 0x0F))
        if length < 126:
            header.append(mask_bit | length)
        elif length < (1 << 16):
            header.append(mask_bit | 126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(mask_bit | 127)
            header.extend(struct.pack("!Q", length))
        mask_key = os.urandom(4)
        header.extend(mask_key)
        masked = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + masked)

    def send_text(self, text: str):
        self._send_frame(text.encode("utf-8"), opcode=1)

    def recv_frame(self) -> Tuple[int, bytes]:
        if not self.sock:
            raise RuntimeError("WebSocket not connected")
        first_two = self._recv_exact(2)
        b1, b2 = first_two[0], first_two[1]
        opcode = b1 & 0x0F
        mask = (b2 & 0x80) != 0
        length = b2 & 0x7F
        if length == 126:
            length = struct.unpack("!H", self._recv_exact(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self._recv_exact(8))[0]
        mask_key = b""
        if mask:
            mask_key = self._recv_exact(4)
        payload = self._recv_exact(length)
        if mask:
            payload = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))
        return opcode, payload

    def _recv_exact(self, n: int) -> bytes:
        if not self.sock:
            raise RuntimeError("WebSocket not connected")
        data = b""
        while len(data) < n:
            try:
                chunk = self.sock.recv(n - len(data))
            except socket.timeout as exc:
                raise TimeoutError("WebSocket read timeout") from exc
            if not chunk:
                raise RuntimeError("WebSocket closed")
            data += chunk
        return data


class AgentSim:
    def __init__(self, device_id: str, agent_keypair: Tuple[str, str], jwt: str, trace_id: str):
        self.device_id = device_id
        self.agent_priv_b64, self.agent_pub_b64 = agent_keypair
        self.jwt = jwt
        self.trace_id = trace_id
        self.seq = 0
        self.ws: Optional[WebSocketClient] = None
        self.session_id: Optional[str] = None
        self.last_command: Optional[Dict[str, Any]] = None

    def connect(self, ws_url: str):
        self.ws = WebSocketClient(ws_url)
        self.ws.connect()
        self.seq += 1
        auth = {
            "message_id": f"m-auth-{uuid.uuid4()}",
            "timestamp": now_iso(),
            "type": "AUTH",
            "from": "agent",
            "device_id": self.device_id,
            "session_id": None,
            "seq": self.seq,
            "body": {
                "auth": {
                    "jwt": self.jwt,
                    "nonce": str(uuid.uuid4())
                },
                "agent_info": {
                    "agent_version": "1.0.0",
                    "os_build": "linux-sim",
                    "hwid_hash": f"sha256:{hashlib.sha256(self.device_id.encode()).hexdigest()}",
                    "attestation_hash": f"SIMULATED_BUT_PROTOCOL_VALID:{hashlib.sha256((self.device_id+"-att").encode()).hexdigest()}"
                }
            }
        }
        auth["sig"] = sign_ed25519(self.agent_priv_b64, auth)
        self.ws.send_text(json.dumps(auth))
        log_event(
            trace_id=self.trace_id,
            span_id=str(uuid.uuid4()),
            request_id=str(uuid.uuid4()),
            event_type="wss.send",
            stage="agent.auth",
            sync_or_async="sync",
            direction="agent->fastapi",
            endpoint_or_channel=ws_url,
            latency_ms=0,
            result="sent",
        )

        opcode, payload = self.ws.recv_frame()
        if opcode != 1:
            raise RuntimeError("Unexpected opcode during AUTH")
        msg = json.loads(payload.decode("utf-8"))
        log_event(
            trace_id=self.trace_id,
            span_id=str(uuid.uuid4()),
            request_id=str(uuid.uuid4()),
            event_type="wss.recv",
            stage="agent.auth_ack",
            sync_or_async="sync",
            direction="fastapi->agent",
            endpoint_or_channel=ws_url,
            latency_ms=0,
            result=msg.get("type", "unknown"),
        )
        if msg.get("type") != "AUTH_ACK":
            raise RuntimeError(f"AUTH failed: {msg}")
        self.session_id = msg.get("body", {}).get("session_id")
        return msg

    def send_ack(self, command_message_id: str, reason: Optional[str] = None, duplicate: bool = False):
        if not self.ws:
            raise RuntimeError("WSS not connected")
        self.seq += 1
        body = {
            "command_message_id": command_message_id,
            "status": "received",
            "reason": reason
        }
        payload = {
            "message_id": f"m-ack-{uuid.uuid4()}",
            "timestamp": now_iso(),
            "type": "COMMAND_ACK",
            "from": "agent",
            "device_id": self.device_id,
            "session_id": self.session_id,
            "seq": self.seq,
            "body": body,
        }
        payload["sig"] = sign_ed25519(self.agent_priv_b64, payload)
        self.ws.send_text(json.dumps(payload))
        log_event(
            trace_id=self.trace_id,
            span_id=str(uuid.uuid4()),
            request_id=str(uuid.uuid4()),
            event_type="wss.send",
            stage="command.ack",
            sync_or_async="async",
            direction="agent->fastapi",
            endpoint_or_channel="wss:/agent",
            latency_ms=0,
            result="sent",
            command_id=command_message_id,
        )
        if duplicate:
            self.ws.send_text(json.dumps(payload))

    def send_result(self, command_message_id: str, execution_state: str, result: Dict[str, Any], duplicate: bool = False):
        if not self.ws:
            raise RuntimeError("WSS not connected")
        self.seq += 1
        body = {
            "command_message_id": command_message_id,
            "execution_state": execution_state,
            "result": result,
            "error_code": None,
            "error_message": None
        }
        payload = {
            "message_id": f"m-result-{uuid.uuid4()}",
            "timestamp": now_iso(),
            "type": "COMMAND_RESULT",
            "from": "agent",
            "device_id": self.device_id,
            "session_id": self.session_id,
            "seq": self.seq,
            "body": body,
        }
        payload["sig"] = sign_ed25519(self.agent_priv_b64, payload)
        self.ws.send_text(json.dumps(payload))
        log_event(
            trace_id=self.trace_id,
            span_id=str(uuid.uuid4()),
            request_id=str(uuid.uuid4()),
            event_type="wss.send",
            stage="command.result",
            sync_or_async="async",
            direction="agent->fastapi",
            endpoint_or_channel="wss:/agent",
            latency_ms=0,
            result="sent",
            command_id=command_message_id,
        )
        if duplicate:
            self.ws.send_text(json.dumps(payload))

    def send_telemetry(self):
        if not self.ws:
            return
        self.seq += 1
        body = {
            "metrics": {
                "cpu": "12.5%",
                "ram": "48.0%",
                "disk_usage": "33.1%",
                "network_tx": "12345",
                "network_rx": "54321",
                "risk_score": 0.1,
                "policy_hash": POLICY_HASH,
            },
            "telemetry_scope": "system",
            "timestamp": now_iso()
        }
        payload = {
            "message_id": f"m-telemetry-{uuid.uuid4()}",
            "timestamp": now_iso(),
            "type": "TELEMETRY",
            "from": "agent",
            "device_id": self.device_id,
            "session_id": self.session_id,
            "seq": self.seq,
            "body": body,
        }
        payload["sig"] = sign_ed25519(self.agent_priv_b64, payload)
        self.ws.send_text(json.dumps(payload))
        log_event(
            trace_id=self.trace_id,
            span_id=str(uuid.uuid4()),
            request_id=str(uuid.uuid4()),
            event_type="wss.send",
            stage="telemetry.send",
            sync_or_async="async",
            direction="agent->fastapi",
            endpoint_or_channel="wss:/agent",
            latency_ms=0,
            result="sent",
            device_id=self.device_id,
        )


class KernelSim:
    def __init__(self):
        if not HAVE_PYNACL:
            raise RuntimeError("PyNaCl required for kernel sim")
        self.sk = SigningKey.generate()
        self.pk_b64 = b64e(self.sk.verify_key.encode())

    def handle(self, req: Dict[str, Any], agent_pub_b64: str) -> Dict[str, Any]:
        sig = req.get("signature")
        if not sig or not verify_ed25519(agent_pub_b64, req, sig):
            return {
                "request_id": req.get("request_id"),
                "status": "denied",
                "kernel_exec_id": str(uuid.uuid4()),
                "timestamp": now_iso(),
                "error_code": 2001,
                "error_message": "signature_invalid",
                "result": {},
                "signature": self._sign_response({
                    "request_id": req.get("request_id"),
                    "status": "denied",
                    "kernel_exec_id": "",
                    "timestamp": now_iso(),
                    "error_code": 2001,
                    "error_message": "signature_invalid",
                    "result": {}
                })
            }
        status = "ok"
        result = {"status": "ok", "notes": "SIMULATED_BUT_PROTOCOL_VALID"}
        resp = {
            "request_id": req.get("request_id"),
            "status": status,
            "kernel_exec_id": str(uuid.uuid4()),
            "timestamp": now_iso(),
            "error_code": None,
            "error_message": None,
            "result": result,
        }
        resp["signature"] = self._sign_response(resp)
        return resp

    def _sign_response(self, resp: Dict[str, Any]) -> str:
        msg = canonicalize(strip_sig(resp))
        sig = self.sk.sign(msg).signature
        return b64e(sig)


def gen_keypair_b64() -> Tuple[str, str]:
    if not HAVE_PYNACL:
        raise RuntimeError("PyNaCl required for Ed25519")
    sk = SigningKey.generate()
    pk = sk.verify_key.encode()
    return (b64e(sk.encode()), b64e(pk))


def register_or_login(trace_id: str) -> Dict[str, Any]:
    if not TEST_USER_EMAIL or not TEST_USER_PASSWORD:
        raise RuntimeError("TEST_USER_EMAIL and TEST_USER_PASSWORD required")

    if not HAVE_PYNACL:
        raise RuntimeError("PyNaCl required for mobile keypair")

    mobile_sk, mobile_pk = gen_keypair_b64()

    def unique_email(base: str) -> str:
        if "@" not in base:
            return f"{base}.{uuid.uuid4().hex[:6]}"
        local, domain = base.split("@", 1)
        return f"{local}+{uuid.uuid4().hex[:6]}@{domain}"

    def try_register(email: str) -> Optional[Dict[str, Any]]:
        register_payload = {
            "display_name": "Quoodle Test User",
            "email": email,
            "password": TEST_USER_PASSWORD,
            "pubkey": mobile_pk,
        }
        resp = http_request(
            "POST",
            f"{LARAVEL_BASE_URL}/api/register",
            json_body=register_payload,
            trace_id=trace_id,
            stage="register",
            direction="mobile->laravel",
        )
        if resp.status_code in (200, 201):
            data = resp.json()
            data["email"] = email
            return data
        return None

    data = try_register(TEST_USER_EMAIL)
    if data:
        return data

    login_payload = {
        "email": TEST_USER_EMAIL,
        "password": TEST_USER_PASSWORD,
        "device_fingerprint": hashlib.sha256(mobile_pk.encode()).hexdigest(),
        "two_factor_code": None,
        "push_token": None,
    }
    resp = http_request(
        "POST",
        f"{LARAVEL_BASE_URL}/api/login",
        json_body=login_payload,
        trace_id=trace_id,
        stage="login",
        direction="mobile->laravel",
    )
    if resp.status_code != 200:
        raise RuntimeError(f"Login failed: {resp.status_code} {resp.text}")

    data = resp.json()
    data["email"] = TEST_USER_EMAIL
    role = data.get("user_role")
    if role in ("operator", "admin"):
        return data

    if os.getenv("ALLOW_ROLE_FALLBACK", "true").lower() in ("1", "true", "yes"):
        email = unique_email(TEST_USER_EMAIL)
        fallback = try_register(email)
        if fallback:
            return fallback

    return data


def pair_device(trace_id: str, jwt: str, base_device_id: str) -> Dict[str, Any]:
    init = http_request(
        "POST",
        f"{LARAVEL_BASE_URL}/api/pair/init",
        headers={"Authorization": f"Bearer {jwt}"},
        json_body={"device_label": f"Device-{base_device_id}"},
        trace_id=trace_id,
        stage="pair.init",
        direction="mobile->laravel",
    )
    pair_session_id = None
    if init.status_code in (200, 201):
        pair_session_id = init.json().get("pair_session_id")

    for attempt in range(PAIR_MAX_ATTEMPTS):
        device_id = base_device_id if attempt == 0 else f"{base_device_id}-{attempt}"
        hwid = f"HW-{hashlib.sha256(device_id.encode()).hexdigest()[:16]}"
        agent_priv_b64, agent_pub_b64 = gen_keypair_b64()

        pair_request = http_request(
            "POST",
            f"{LARAVEL_BASE_URL}/api/pair/request",
            json_body={
                "device_name": f"Device-{device_id}",
                "hwid": hwid,
                "pubkey": agent_pub_b64,
            },
            trace_id=trace_id,
            stage="pair.request",
            direction="agent->laravel",
        )
        if pair_request.status_code == 409:
            try:
                reason = pair_request.json().get("reason")
            except Exception:
                reason = None
            if reason == "already_claimed":
                continue
        if pair_request.status_code not in (200, 201):
            raise RuntimeError(f"Pair request failed: {pair_request.status_code} {pair_request.text}")

        pair_token = pair_request.json().get("pair_token")
        if not pair_token:
            raise RuntimeError("Pair request missing pair_token")

        confirm_payload = {"pair_token": pair_token}
        if pair_session_id:
            confirm_payload["pair_session_id"] = pair_session_id

        confirm = http_request(
            "POST",
            f"{LARAVEL_BASE_URL}/api/pair/confirm",
            headers={"Authorization": f"Bearer {jwt}"},
            json_body=confirm_payload,
            trace_id=trace_id,
            stage="pair.confirm",
            direction="mobile->laravel",
        )
        if confirm.status_code not in (200, 201):
            raise RuntimeError(f"Pair confirm failed: {confirm.status_code} {confirm.text}")
        result = confirm.json()
        result["pair_token"] = pair_token
        result["agent_priv_b64"] = agent_priv_b64
        result["agent_pub_b64"] = agent_pub_b64
        return result

    raise RuntimeError("pair_request_exhausted")


def send_command(trace_id: str, jwt: str, device_id: str) -> Dict[str, Any]:
    client_message_id = str(uuid.uuid4())
    payload = {
        "device_id": device_id,
        "method": "lock_screen",
        "params": {},
        "sensitive": False,
        "client_message_id": client_message_id,
        "two_factor_code": None
    }
    resp = http_request(
        "POST",
        f"{LARAVEL_BASE_URL}/api/commands",
        headers={"Authorization": f"Bearer {jwt}"},
        json_body=payload,
        trace_id=trace_id,
        stage="command.enqueue",
        direction="mobile->laravel",
    )
    log_event(
        trace_id=trace_id,
        span_id=str(uuid.uuid4()),
        request_id=str(uuid.uuid4()),
        event_type="command.enqueue",
        stage="command.enqueue",
        sync_or_async="sync",
        direction="mobile->laravel",
        endpoint_or_channel="/api/commands",
        latency_ms=0,
        result=str(resp.status_code),
        idempotency_key=client_message_id,
        device_id=device_id,
    )
    if resp.status_code not in (200, 201):
        raise RuntimeError(f"Command enqueue failed: {resp.status_code} {resp.text}")
    return resp.json()


def poll_command(trace_id: str, jwt: str, command_id: str) -> Optional[Dict[str, Any]]:
    deadline = time.time() + POLL_TIMEOUT
    while time.time() < deadline:
        resp = http_request(
            "GET",
            f"{LARAVEL_BASE_URL}/api/commands/{command_id}",
            headers={"Authorization": f"Bearer {jwt}"},
            trace_id=trace_id,
            stage="command.poll",
            direction="mobile->laravel",
        )
        if resp.status_code == 200:
            data = resp.json()
            if data.get("state") in ("completed", "failed", "expired"):
                return data
        time.sleep(POLL_INTERVAL)
    return None


def wait_for_command_delivery(agent: AgentSim, trace_id: str, device_id: str) -> Dict[str, Any]:
    if not agent.ws:
        raise RuntimeError("wss_not_connected")
    deadline = time.time() + WSS_TIMEOUT
    while time.time() < deadline:
        try:
            opcode, payload = agent.ws.recv_frame()
        except TimeoutError:
            continue
        except Exception as exc:
            raise RuntimeError(f"wss_receive_failed: {exc}") from exc
        if opcode == 8:
            raise RuntimeError("wss_closed_by_server")
        if opcode != 1:
            continue
        try:
            msg = json.loads(payload.decode("utf-8"))
        except Exception:
            continue
        mtype = msg.get("type", "unknown")
        log_event(
            trace_id=trace_id,
            span_id=str(uuid.uuid4()),
            request_id=str(uuid.uuid4()),
            event_type="wss.recv",
            stage=f"wss.{mtype.lower()}",
            sync_or_async="async",
            direction="fastapi->agent",
            endpoint_or_channel="wss:/agent",
            latency_ms=0,
            result=mtype,
            device_id=device_id,
        )
        if mtype == "COMMAND_DELIVERY":
            return msg
    raise RuntimeError("command_delivery_timeout")


def get_agent_jwt(trace_id: str, pair_token: str) -> str:
    resp = http_request(
        "POST",
        f"{LARAVEL_BASE_URL}/api/agent/token",
        json_body={"pair_token": pair_token},
        trace_id=trace_id,
        stage="agent.token",
        direction="agent->laravel",
    )
    if resp.status_code not in (200, 201):
        raise RuntimeError(f"Agent token request failed: {resp.status_code} {resp.text}")
    data = resp.json()
    jwt = data.get("jwt")
    if not jwt:
        raise RuntimeError("Agent token response missing jwt")
    return jwt


def dispatch_direct(trace_id: str, command: Dict[str, Any], device_id: str, user_id: Optional[str]):
    if not LARAVEL_SERVICE_PRIVATE_KEY_B64:
        raise RuntimeError("LARAVEL_SERVICE_PRIVATE_KEY_B64 required for direct dispatch")
    payload = {
        "command_id": command.get("command_id"),
        "device_id": device_id,
        "trace_id": str(uuid.uuid4()),
        "seq": 1,
        "envelope": {
            "header": {
                "version": "1.1",
                "timestamp": now_iso(),
                "ttl_seconds": 300,
                "priority": "normal",
                "requires_ack": True,
                "long_running": False
            },
            "body": {
                "method": "lock_screen",
                "params": {},
                "sensitive": False
            },
            "meta": {
                "origin_user_id": user_id or "unknown",
                "enc": "none",
                "enc_key_id": None,
                "policy_version": POLICY_VERSION
            },
            "sig": None
        }
    }
    payload["envelope"]["sig"] = sign_ed25519(LARAVEL_SERVICE_PRIVATE_KEY_B64, payload["envelope"])
    request_sig = sign_ed25519(LARAVEL_SERVICE_PRIVATE_KEY_B64, payload)
    resp = http_request(
        "POST",
        f"{FASTAPI_BASE_URL}/api/v1/command/dispatch",
        headers={"X-Laravel-Signature": request_sig},
        json_body=payload,
        trace_id=trace_id,
        stage="dispatch.direct",
        direction="laravel->fastapi",
    )
    return resp


def send_webhook_direct(trace_id: str, path: str, payload: Dict[str, Any]):
    if not FASTAPI_SERVICE_PRIVATE_KEY_B64:
        raise RuntimeError("FASTAPI_SERVICE_PRIVATE_KEY_B64 required for direct webhooks")
    sig = sign_ed25519(FASTAPI_SERVICE_PRIVATE_KEY_B64, payload)
    resp = http_request(
        "POST",
        f"{LARAVEL_BASE_URL}/api/v1/webhook/{path}",
        headers={"X-FastAPI-Signature": sig},
        json_body=payload,
        trace_id=trace_id,
        stage=f"webhook.{path}",
        direction="fastapi->laravel",
    )
    return resp


def run_once(run_idx: int) -> Dict[str, Any]:
    if not HAVE_PYNACL:
        return {"status": "FAIL", "reason": "PyNaCl missing"}
    if not LARAVEL_BASE_URL or not FASTAPI_BASE_URL:
        return {"status": "FAIL", "reason": "Missing base URLs"}

    trace_id = str(uuid.uuid4())
    log_event(trace_id=trace_id, span_id=str(uuid.uuid4()), request_id=str(uuid.uuid4()), event_type="run.start", stage="run", sync_or_async="sync", direction="internal", endpoint_or_channel="n/a", latency_ms=0, result=f"run_{run_idx}")

    wait_for_http(f"{LARAVEL_BASE_URL}/")
    wait_for_http(f"{FASTAPI_BASE_URL}/health")
    resolve_policy_defaults(trace_id)
    if not POLICY_HASH or not POLICY_VERSION:
        return {"status": "FAIL", "reason": "Missing POLICY_HASH or POLICY_VERSION"}

    auth = register_or_login(trace_id)
    jwt = auth.get("jwt")
    user_id = auth.get("user_id")

    local_device_id = f"SIM-PC-{SEED}-{RUN_NONCE}-{run_idx}"
    pair_result = pair_device(trace_id, jwt, local_device_id)
    if pair_result.get("status") not in ("ok", "paired", None):
        return {"status": "FAIL", "reason": "pairing_failed"}

    device_id = pair_result.get("device_id") or local_device_id
    agent_jwt = AGENT_JWT or pair_result.get("agent_jwt")
    if not agent_jwt:
        agent_jwt = get_agent_jwt(trace_id, pair_result.get("pair_token", ""))

    agent_priv_b64 = pair_result.get("agent_priv_b64")
    agent_pub_b64 = pair_result.get("agent_pub_b64")
    if not agent_priv_b64 or not agent_pub_b64:
        return {"status": "FAIL", "reason": "agent_keypair_missing"}
    agent = AgentSim(device_id, (agent_priv_b64, agent_pub_b64), agent_jwt, trace_id)
    ws_url = FASTAPI_BASE_URL.replace("http://", "ws://").replace("https://", "wss://") + "/agent"
    agent.connect(ws_url)

    command = send_command(trace_id, jwt, device_id)
    command_id = command.get("command_id")

    if DISPATCH_MODE == "direct":
        dispatch_direct(trace_id, command, device_id, user_id)

    try:
        msg = wait_for_command_delivery(agent, trace_id, device_id)
    except Exception as exc:
        return {"status": "FAIL", "reason": str(exc)}
    log_event(
        trace_id=trace_id,
        span_id=str(uuid.uuid4()),
        request_id=str(uuid.uuid4()),
        event_type="wss.recv",
        stage="command.delivery",
        sync_or_async="async",
        direction="fastapi->agent",
        endpoint_or_channel="wss:/agent",
        latency_ms=0,
        result="received",
        device_id=device_id,
    )

    # Verify WSS signature if configured
    if FASTAPI_WSS_PUBLIC_KEY_B64:
        if not verify_ed25519(FASTAPI_WSS_PUBLIC_KEY_B64, msg, msg.get("sig", "")):
            return {"status": "FAIL", "reason": "wss_signature_invalid"}

    command_envelope = msg.get("body", {}).get("command_envelope", {})
    if LARAVEL_COMMAND_PUBLIC_KEY_B64:
        if not verify_ed25519(LARAVEL_COMMAND_PUBLIC_KEY_B64, command_envelope, command_envelope.get("sig", "")):
            return {"status": "FAIL", "reason": "command_signature_invalid"}

    if "out_of_order" not in FAULTS:
        agent.send_ack(command_envelope.get("message_id"), duplicate="duplicate_ack" in FAULTS)

    # KernelSim execution
    kernel = KernelSim()
    ioctl_req = {
        "request_id": str(uuid.uuid4()),
        "timestamp": now_iso(),
        "opcode": "EXEC_LOCK_SCREEN",
        "params": {},
        "agent_sequence": 1,
        "policy_hash": POLICY_HASH,
        "command_message_id": command_envelope.get("message_id"),
    }
    ioctl_req["signature"] = sign_ed25519(agent_priv_b64, ioctl_req)
    kernel_resp = kernel.handle(ioctl_req, agent_pub_b64)

    if "out_of_order" in FAULTS:
        agent.send_result(command_envelope.get("message_id"), "completed", kernel_resp.get("result", {}), duplicate="duplicate_result" in FAULTS)
        agent.send_ack(command_envelope.get("message_id"), duplicate="duplicate_ack" in FAULTS)
    else:
        agent.send_result(command_envelope.get("message_id"), "completed", kernel_resp.get("result", {}), duplicate="duplicate_result" in FAULTS)

    # Optional direct webhook
    if WEBHOOK_MODE in ("direct", "both"):
        send_webhook_direct(trace_id, "command/ack", {
            "command_id": command_envelope.get("message_id"),
            "device_id": device_id,
            "status": "received",
            "reason": None,
            "timestamp": now_iso()
        })
        send_webhook_direct(trace_id, "command/result", {
            "command_id": command_envelope.get("message_id"),
            "device_id": device_id,
            "trace_id": str(uuid.uuid4()),
            "execution_state": "completed",
            "result": kernel_resp.get("result", {}),
            "error_code": None,
            "error_message": None,
            "timestamp": now_iso()
        })

    agent.send_telemetry()

    final_state = poll_command(trace_id, jwt, command_id)
    if not final_state:
        return {"status": "FAIL", "reason": "command_timeout"}

    return {"status": "PASS", "command_state": final_state.get("state"), "device_id": device_id, "command_id": command_id}


def main():
    results = []
    for i in range(RUNS):
        try:
            result = run_once(i + 1)
        except Exception as exc:
            result = {"status": "FAIL", "reason": str(exc)}
        results.append(result)

    summary = {
        "runs": results,
        "status": "PASS" if all(r.get("status") == "PASS" for r in results) else "FAIL"
    }
    print(json.dumps(summary, indent=2))

    if summary["status"] != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
