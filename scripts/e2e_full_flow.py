#!/usr/bin/env python3
"""
End-to-End Verification Script for Quoodle System

This script simulates:
1. Mobile Client: Login, Device Pairing, Command Dispatch
2. Agent Emulator: WSS Connection, Authentication, Command Execution, ACK + RESULT

It validates the full command lifecycle from Control Plane through Gateway.
"""

import asyncio
import base64
import getpass
import json
import logging
import os
import platform
import shutil
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

# Try to import dependencies
try:
    import websockets
    import httpx
    from nacl.signing import SigningKey
    from nacl.encoding import Base64Encoder
except ImportError as e:
    print(f"❌ Missing dependency: {e}")
    print("Please install: pip install websockets httpx pynacl")
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]

# Configuration
LARAVEL_URL = os.getenv("LARAVEL_URL", "http://localhost:8080/api")
GATEWAY_URL = os.getenv("GATEWAY_URL", "http://localhost:8000")
GATEWAY_WS_URL = os.getenv("GATEWAY_WS_URL", "ws://localhost:8000/agent")
DEVICE_LABEL = os.getenv("DEVICE_LABEL", "Quoodle E2E Device")
TEST_USER_EMAIL = os.getenv("TEST_USER_EMAIL", "test@example.com")
TEST_USER_PASSWORD = os.getenv("TEST_USER_PASSWORD", "password")
TEST_USER_ROLE = os.getenv("TEST_USER_ROLE", "operator")
SCREENSHOT_USER_ROLE = os.getenv("SCREENSHOT_USER_ROLE", TEST_USER_ROLE)
SCREENSHOT_TWO_FACTOR_CODE = os.getenv("SCREENSHOT_TWO_FACTOR_CODE", "")
ALLOWED_ROOT = os.path.realpath(os.getenv("ALLOWED_ROOT", "/home/ela/Work-Force"))
COMMAND_TIMEOUT_SECONDS = int(os.getenv("COMMAND_TIMEOUT_SECONDS", "30"))
COMMAND_POLL_INTERVAL = float(os.getenv("COMMAND_POLL_INTERVAL", "2.0"))
AGENT_VERSION = os.getenv("QUOODLE_AGENT_VERSION", "linux-agent-emulator")
ARTIFACT_DIR = os.path.realpath(os.getenv("QUOODLE_ARTIFACT_DIR", os.path.join(ALLOWED_ROOT, "artifacts")))

# Keys for service-to-service signing (matches docker-compose)
LARAVEL_SERVICE_PRIVATE_KEY_B64 = os.getenv("LARAVEL_SERVICE_PRIVATE_KEY_B64", "")

# Setup Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger("E2E")


COMMAND_SUITE = [
    {"method": "sysinfo", "params": {}},
    {"method": "list_processes", "params": {"limit": 15}},
    {"method": "get_users", "params": {}},
    {"method": "get_sessions", "params": {}},
    {"method": "list_services", "params": {"limit": 25}},
    {"method": "network_info", "params": {}},
    {"method": "list_mounts", "params": {}},
    {"method": "get_env_fingerprint", "params": {}},
    {"method": "screenshot", "params": {}},
    {"method": "list_files", "params": {"path": "Quoodle", "limit": 25}},
    {"method": "hash_file", "params": {"path": "Quoodle/README.md", "algo": "sha256"}},
]


def iso_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load_laravel_private_key_b64() -> str:
    if LARAVEL_SERVICE_PRIVATE_KEY_B64:
        return LARAVEL_SERVICE_PRIVATE_KEY_B64
    compose_path = ROOT / "docker-compose.yml"
    if not compose_path.exists():
        raise RuntimeError("docker-compose.yml not found and LARAVEL_SERVICE_PRIVATE_KEY_B64 not set")
    for line in compose_path.read_text(encoding="utf-8").splitlines():
        if "LARAVEL_SERVICE_PRIVATE_KEY_B64" in line:
            return line.split(":", 1)[1].strip().strip('"')
    raise RuntimeError("LARAVEL_SERVICE_PRIVATE_KEY_B64 not found in docker-compose.yml")


def compute_signature(payload: dict, signing_key: SigningKey) -> str:
    """Compute Ed25519 signature over canonical JSON."""
    clean = {k: v for k, v in payload.items() if k != "sig"}
    canonical = json.dumps(
        clean,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
        ensure_ascii=False,
    ).encode()
    signed = signing_key.sign(canonical)
    return base64.b64encode(signed.signature).decode()


def sign_laravel_request(payload: dict) -> str:
    """Compute signature for Laravel -> Gateway requests."""
    key_bytes = base64.b64decode(load_laravel_private_key_b64())
    seed = key_bytes[:32]
    signer = SigningKey(seed)
    canonical = json.dumps(
        payload,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
        ensure_ascii=False,
    ).encode()
    signed = signer.sign(canonical)
    return base64.b64encode(signed.signature).decode()


def read_os_release() -> str:
    path = "/etc/os-release"
    if not os.path.exists(path):
        return platform.platform()
    try:
        return Path(path).read_text(encoding="utf-8").strip()
    except Exception:
        return platform.platform()


def hashlib_sha256(data: bytes) -> str:
    import hashlib

    h = hashlib.sha256()
    h.update(data)
    return h.hexdigest()


def compute_attestation_hash(device_id: str, pubkey_b64: str) -> str:
    parts = [device_id, pubkey_b64, platform.node()]
    machine_id_path = "/etc/machine-id"
    if os.path.exists(machine_id_path):
        try:
            parts.append(Path(machine_id_path).read_text(encoding="utf-8").strip())
        except Exception:
            pass
    raw = "|".join(parts).encode("utf-8")
    return "sha256:" + hashlib_sha256(raw)


def resolve_under_root(rel_path: str) -> str:
    if not rel_path:
        raise ValueError("path required")
    if rel_path.startswith("/"):
        raise ValueError("absolute paths not allowed")
    full = os.path.realpath(os.path.join(ALLOWED_ROOT, rel_path))
    if not full.startswith(ALLOWED_ROOT.rstrip(os.sep) + os.sep):
        raise ValueError("path escapes allowed root")
    return full


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def run_command(cmd: list[str]) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except Exception as exc:
        return 1, "", str(exc)


def list_processes(limit: int = 20) -> list[dict]:
    rc, out, _ = run_command(["ps", "-eo", "pid,comm,user,args"])
    if rc != 0:
        return []
    lines = out.splitlines()[1 : limit + 1]
    rows = []
    for line in lines:
        parts = line.strip().split(None, 3)
        if len(parts) < 3:
            continue
        pid = int(parts[0]) if parts[0].isdigit() else 0
        name = parts[1]
        user = parts[2]
        cmdline = parts[3] if len(parts) > 3 else ""
        rows.append({"pid": pid, "name": name, "user": user, "cmdline": cmdline})
    return rows


def list_users() -> list[dict]:
    rc, out, _ = run_command(["who"])
    if rc != 0:
        return []
    entries = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            entries.append({"user": parts[0], "tty": parts[1], "since": " ".join(parts[2:4])})
    return entries


def list_sessions() -> list[dict]:
    if not shutil.which("loginctl"):
        return []
    rc, out, _ = run_command(["loginctl", "list-sessions", "--no-legend"])
    if rc != 0:
        return []
    sessions = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            sessions.append({"session": parts[0], "uid": parts[1], "user": parts[2] if len(parts) > 2 else None})
    return sessions


def list_services(limit: int = 50) -> list[dict]:
    if not shutil.which("systemctl"):
        return []
    rc, out, _ = run_command(["systemctl", "list-units", "--type=service", "--all", "--no-legend", "--no-pager"])
    if rc != 0:
        return []
    services = []
    for line in out.splitlines()[:limit]:
        parts = line.split(None, 4)
        if len(parts) >= 4:
            services.append({
                "unit": parts[0],
                "load": parts[1],
                "active": parts[2],
                "sub": parts[3],
                "description": parts[4] if len(parts) > 4 else "",
            })
    return services


def list_mounts(limit: int = 100) -> list[dict]:
    mounts = []
    try:
        with open("/proc/mounts", "r", encoding="utf-8") as f:
            for line in f.readlines()[:limit]:
                parts = line.split()
                if len(parts) >= 3:
                    mounts.append({"source": parts[0], "target": parts[1], "fstype": parts[2]})
    except Exception:
        pass
    return mounts


def network_info() -> dict:
    info = {"interfaces": [], "routes": []}
    if shutil.which("ip"):
        rc, out, _ = run_command(["ip", "-j", "addr"])
        if rc == 0 and out:
            try:
                info["interfaces"] = json.loads(out)
            except Exception:
                info["interfaces"] = []
        rc, out, _ = run_command(["ip", "-j", "route"])
        if rc == 0 and out:
            try:
                info["routes"] = json.loads(out)
            except Exception:
                info["routes"] = []
    return info


def env_fingerprint() -> dict:
    return {
        "desktop": os.getenv("XDG_CURRENT_DESKTOP"),
        "session": os.getenv("XDG_SESSION_DESKTOP"),
        "session_type": os.getenv("XDG_SESSION_TYPE"),
        "display": os.getenv("DISPLAY"),
        "active_user": getpass.getuser(),
    }


def list_files(rel_path: str, limit: int = 50) -> list[dict]:
    path = resolve_under_root(rel_path)
    entries = []
    try:
        with os.scandir(path) as it:
            for entry in it:
                stat = entry.stat()
                entries.append({
                    "path": os.path.relpath(entry.path, ALLOWED_ROOT),
                    "is_dir": entry.is_dir(),
                    "size": int(stat.st_size),
                    "mtime": int(stat.st_mtime),
                })
                if len(entries) >= limit:
                    break
    except Exception:
        pass
    return entries


def hash_file(rel_path: str, algo: str = "sha256") -> dict:
    import hashlib

    path = resolve_under_root(rel_path)
    h = hashlib.new(algo)
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return {"algo": algo, "hash": h.hexdigest()}


def get_uptime_seconds() -> int | None:
    try:
        with open("/proc/uptime", "r", encoding="utf-8") as f:
            return int(float(f.read().split()[0]))
    except Exception:
        return None


def capture_screenshot() -> dict:
    ensure_dir(ARTIFACT_DIR)
    filename = f"screenshot-{int(time.time())}.png"
    path = os.path.join(ARTIFACT_DIR, filename)
    session_type = os.getenv("XDG_SESSION_TYPE", "")
    cmd = None
    if session_type == "wayland" and shutil.which("grim"):
        cmd = ["grim", path]
    elif shutil.which("gnome-screenshot"):
        cmd = ["gnome-screenshot", "-f", path]
    elif shutil.which("scrot"):
        cmd = ["scrot", path]
    elif shutil.which("import"):
        cmd = ["import", "-window", "root", path]
    if not cmd:
        raise RuntimeError("no screenshot tool available")
    rc, _, err = run_command(cmd)
    if rc != 0:
        raise RuntimeError(err or "screenshot failed")
    rel_path = None
    if path.startswith(ALLOWED_ROOT.rstrip(os.sep) + os.sep):
        rel_path = os.path.relpath(path, ALLOWED_ROOT)
    sha256 = None
    try:
        sha256 = hashlib_sha256(Path(path).read_bytes())
    except Exception:
        sha256 = None
    return {"path": path, "relative_path": rel_path, "artifact_id": filename, "sha256": sha256}


class AgentEmulator:
    def __init__(self, device_id: str, jwt_token: str, signing_key: SigningKey | None = None):
        self.device_id = device_id
        self.jwt_token = jwt_token
        self.signing_key = signing_key or SigningKey.generate()
        self.verify_key = self.signing_key.verify_key
        self.pubkey_b64 = self.verify_key.encode(encoder=Base64Encoder).decode("utf-8")
        self.session_id = None
        self.websocket = None
        self.running = False
        self.seq = 0
        self.command_events: dict[str, asyncio.Event] = {}
        self.command_results: dict[str, dict] = {}
        self.policy_hash: str | None = None
        self.last_cpu_total = None
        self.last_cpu_idle = None
        self.last_net_tx = None
        self.last_net_rx = None
        self.last_telemetry_time = None
        self.send_lock = asyncio.Lock()

    def next_seq(self) -> int:
        self.seq += 1
        return self.seq

    async def register_pubkey_with_gateway(self) -> bool:
        logger.info(f"📝 Registering Agent pubkey with Gateway for device: {self.device_id}")
        payload = {"ed25519_pubkey_b64": self.pubkey_b64}
        sig = sign_laravel_request(payload)
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{GATEWAY_URL}/api/v1/admin/device-keys/{self.device_id}",
                json=payload,
                headers={"X-Laravel-Signature": sig},
            )
            if resp.status_code == 200:
                logger.info("✅ Pubkey registered with Gateway")
                return True
            logger.error(f"❌ Failed to register pubkey: {resp.text}")
            return False

    async def fetch_policy_hash(self) -> None:
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.get(f"{GATEWAY_URL}/api/v1/policy/state")
                if resp.status_code == 200:
                    payload = resp.json()
                    self.policy_hash = payload.get("policy_hash")
        except Exception:
            self.policy_hash = None

    def build_auth_envelope(self) -> dict:
        nonce = uuid.uuid4().hex
        os_build = f"{platform.system()} {platform.release()}"
        attestation_hash = compute_attestation_hash(self.device_id, self.pubkey_b64)
        payload = {
            "type": "AUTH",
            "from": "agent",
            "device_id": self.device_id,
            "message_id": f"m-auth-{uuid.uuid4()}",
            "session_id": None,
            "timestamp": iso_timestamp(),
            "body": {
                "auth": {"jwt": self.jwt_token, "nonce": nonce},
                "agent_info": {
                    "agent_version": AGENT_VERSION,
                    "os_build": os_build,
                    "attestation_hash": attestation_hash,
                },
            },
        }
        payload["sig"] = compute_signature(payload, self.signing_key)
        return payload

    async def send_message(self, message: dict, include_seq: bool = True) -> None:
        async with self.send_lock:
            if include_seq:
                message["seq"] = self.next_seq()
            message["sig"] = compute_signature(message, self.signing_key)
            await self.websocket.send(json.dumps(message))

    async def connect(self) -> None:
        logger.info(f"🔌 Connecting to Gateway WSS: {GATEWAY_WS_URL}")
        try:
            self.websocket = await websockets.connect(GATEWAY_WS_URL)
            logger.info("✅ WSS Connected")
            self.running = True
            await self.send_auth()
            asyncio.create_task(self.msg_loop())
        except Exception as e:
            logger.error(f"❌ WSS Connection Failed: {e}")
            raise

    async def send_auth(self) -> None:
        auth_envelope = self.build_auth_envelope()
        await self.websocket.send(json.dumps(auth_envelope))
        logger.info("📤 Sent AUTH envelope")

    async def close(self) -> None:
        if self.websocket:
            logger.info("🔌 Closing WSS Connection...")
            self.running = False
            try:
                await self.websocket.close()
            except Exception:
                pass

    async def msg_loop(self) -> None:
        try:
            async for message in self.websocket:
                data = json.loads(message)
                mtype = data.get("type")

                if mtype == "AUTH_ACK":
                    self.session_id = data.get("body", {}).get("session_id")
                    logger.info(f"✅ Authenticated! Session ID: {self.session_id}")
                    await self.fetch_policy_hash()
                    asyncio.create_task(self.heartbeat_loop())
                    asyncio.create_task(self.telemetry_loop())

                elif mtype == "AUTH_ERROR":
                    err = data.get("body", {})
                    logger.error(f"❌ AUTH Failed: {err.get('error_code')} - {err.get('error_message')}")
                    self.running = False

                elif mtype == "COMMAND_DELIVERY":
                    cmd_envelope = data.get("body", {}).get("command_envelope", {})
                    cmd_id = cmd_envelope.get("message_id")
                    if cmd_id:
                        self.command_events.setdefault(cmd_id, asyncio.Event()).set()
                    await self.handle_command(data)

        except websockets.ConnectionClosed as e:
            logger.info(f"WSS Closed: {e}")
            self.running = False
        except Exception as e:
            logger.error(f"MSG Loop Error: {e}")
            self.running = False

    async def handle_command(self, data: dict) -> None:
        cmd_envelope = data.get("body", {}).get("command_envelope", {})
        msg_id = cmd_envelope.get("message_id")
        method = cmd_envelope.get("body", {}).get("method")
        params = cmd_envelope.get("body", {}).get("params", {})
        header = cmd_envelope.get("header", {})
        trace_id = cmd_envelope.get("trace_id") or msg_id
        requires_ack = bool(header.get("requires_ack", True))

        logger.info(f"⚙️ Executing Method: {method}")

        if requires_ack and msg_id:
            ack = {
                "type": "COMMAND_ACK",
                "from": "agent",
                "device_id": self.device_id,
                "message_id": f"m-ack-{uuid.uuid4()}",
                "session_id": self.session_id,
                "timestamp": iso_timestamp(),
                "seq": self.next_seq(),
                "body": {
                    "command_message_id": msg_id,
                    "status": "received",
                    "reason": None,
                },
            }
            await self.send_message(ack)

        await asyncio.sleep(0.2)

        try:
            details = self.execute_command(method, params)
            execution_state = "completed"
            result = {
                "status": "ok",
                "notes": None,
                "details": details,
            }
            error_code = None
            error_message = None
        except Exception as exc:
            execution_state = "failed"
            result = {
                "status": "error",
                "notes": str(exc),
                "details": {},
            }
            error_code = "ERR_EXECUTION_FAILED"
            error_message = str(exc)

        result_payload = {
            "type": "COMMAND_RESULT",
            "from": "agent",
            "device_id": self.device_id,
            "message_id": f"m-result-{uuid.uuid4()}",
            "session_id": self.session_id,
            "timestamp": iso_timestamp(),
            "seq": self.next_seq(),
            "body": {
                "command_message_id": msg_id,
                "trace_id": trace_id,
                "execution_state": execution_state,
                "result": result,
                "error_code": error_code,
                "error_message": error_message,
            },
        }
        await self.send_message(result_payload)
        if msg_id:
            self.command_results[msg_id] = result_payload
        logger.info("📤 Sent COMMAND_RESULT")

    def execute_command(self, method: str, params: dict) -> dict:
        if method == "sysinfo":
            loadavg = None
            try:
                loadavg = [f"{v:.2f}" for v in os.getloadavg()]
            except Exception:
                loadavg = []
            return {
                "uname": platform.uname()._asdict(),
                "os_release": read_os_release(),
                "uptime_seconds": get_uptime_seconds(),
                "loadavg": loadavg,
            }
        if method == "list_processes":
            return {"processes": list_processes(int(params.get("limit", 15)))}
        if method == "get_users":
            return {"users": list_users()}
        if method == "get_sessions" or method == "list_sessions":
            return {"sessions": list_sessions()}
        if method == "list_services":
            return {"services": list_services(int(params.get("limit", 25)))}
        if method == "network_info" or method == "netinfo":
            return network_info()
        if method == "list_mounts":
            return {"mounts": list_mounts()}
        if method == "get_env_fingerprint":
            return env_fingerprint()
        if method == "screenshot":
            return capture_screenshot()
        if method == "list_files":
            path = params.get("path", "")
            limit = int(params.get("limit", 25))
            return {"entries": list_files(path, limit)}
        if method == "hash_file":
            path = params.get("path", "")
            algo = params.get("algo", "sha256")
            return hash_file(path, algo)
        if method == "download_file":
            path = params.get("path", "")
            max_bytes = int(params.get("max_bytes", 5 * 1024 * 1024))
            full_path = resolve_under_root(path)
            data = Path(full_path).read_bytes()[:max_bytes]
            return {"data_b64": base64.b64encode(data).decode(), "size": len(data)}
        raise RuntimeError(f"Unsupported method: {method}")

    async def heartbeat_loop(self) -> None:
        while self.running and self.session_id:
            body = {
                "status": "alive",
                "policy_hash": self.policy_hash,
                "uptime_seconds": get_uptime_seconds(),
            }
            hb_payload = {
                "type": "HEARTBEAT",
                "from": "agent",
                "device_id": self.device_id,
                "message_id": f"m-hb-{uuid.uuid4()}",
                "session_id": self.session_id,
                "timestamp": iso_timestamp(),
                "body": body,
            }
            try:
                await self.send_message(hb_payload)
                await asyncio.sleep(10)
            except Exception:
                break

    async def telemetry_loop(self) -> None:
        while self.running and self.session_id:
            metrics = self.build_telemetry_metrics()
            body = {
                "timestamp": iso_timestamp(),
                "metrics": metrics,
                "telemetry_scope": "telemetry_basic",
                "policy_hash": self.policy_hash,
            }
            payload = {
                "type": "TELEMETRY",
                "from": "agent",
                "device_id": self.device_id,
                "message_id": f"m-telemetry-{uuid.uuid4()}",
                "session_id": self.session_id,
                "timestamp": iso_timestamp(),
                "body": body,
            }
            try:
                await self.send_message(payload)
                await asyncio.sleep(30)
            except Exception:
                break

    def build_telemetry_metrics(self) -> dict:
        cpu_pct = self.read_cpu_percent()
        mem_pct = self.read_mem_percent()
        disk_pct = self.read_disk_percent()
        tx_mbps, rx_mbps = self.read_net_mbps()
        return {
            "cpu": f"{cpu_pct:.2f}%",
            "ram": f"{mem_pct:.2f}%",
            "disk_usage": f"{disk_pct:.2f}%",
            "network_tx": f"{tx_mbps:.2f} Mbps",
            "network_rx": f"{rx_mbps:.2f} Mbps",
        }

    def read_cpu_percent(self) -> float:
        try:
            with open("/proc/stat", "r", encoding="utf-8") as f:
                parts = f.readline().split()
            total = sum(float(x) for x in parts[1:])
            idle = float(parts[4])
            if self.last_cpu_total is None or self.last_cpu_idle is None:
                self.last_cpu_total = total
                self.last_cpu_idle = idle
                return 0.0
            total_delta = total - self.last_cpu_total
            idle_delta = idle - self.last_cpu_idle
            self.last_cpu_total = total
            self.last_cpu_idle = idle
            if total_delta <= 0:
                return 0.0
            return max(0.0, min(100.0, (1.0 - (idle_delta / total_delta)) * 100.0))
        except Exception:
            return 0.0

    def read_mem_percent(self) -> float:
        try:
            mem_total = 0
            mem_available = 0
            with open("/proc/meminfo", "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("MemTotal"):
                        mem_total = int(line.split()[1])
                    elif line.startswith("MemAvailable"):
                        mem_available = int(line.split()[1])
            if mem_total == 0:
                return 0.0
            used = mem_total - mem_available
            return (used / mem_total) * 100.0
        except Exception:
            return 0.0

    def read_disk_percent(self) -> float:
        try:
            usage = shutil.disk_usage("/")
            if usage.total == 0:
                return 0.0
            return (usage.used / usage.total) * 100.0
        except Exception:
            return 0.0

    def read_net_mbps(self) -> tuple[float, float]:
        try:
            with open("/proc/net/dev", "r", encoding="utf-8") as f:
                lines = f.readlines()[2:]
            rx = 0
            tx = 0
            for line in lines:
                parts = line.strip().split()
                if len(parts) >= 17:
                    rx += int(parts[1])
                    tx += int(parts[9])
            now = time.time()
            if self.last_net_tx is None or self.last_net_rx is None or self.last_telemetry_time is None:
                self.last_net_tx = tx
                self.last_net_rx = rx
                self.last_telemetry_time = now
                return 0.0, 0.0
            delta = max(1.0, now - self.last_telemetry_time)
            tx_mbps = ((tx - self.last_net_tx) * 8.0) / (delta * 1e6)
            rx_mbps = ((rx - self.last_net_rx) * 8.0) / (delta * 1e6)
            self.last_net_tx = tx
            self.last_net_rx = rx
            self.last_telemetry_time = now
            return max(0.0, tx_mbps), max(0.0, rx_mbps)
        except Exception:
            return 0.0, 0.0

    async def wait_for_command(self, command_id: str, timeout: float) -> bool:
        event = self.command_events.setdefault(command_id, asyncio.Event())
        try:
            await asyncio.wait_for(event.wait(), timeout=timeout)
            return True
        except asyncio.TimeoutError:
            return False


async def run_mobile_api_flow() -> tuple[str, str, str, str, SigningKey]:
    """
    Simulates Mobile Client:
    1. Login to get JWT
    2. Init pairing (mobile)
    3. Agent pairing request (device side)
    4. Confirm pairing (mobile) + mint agent JWT

    Returns: (jwt_token, device_id, user_id, agent_jwt, agent_signing_key)
    """
    async with httpx.AsyncClient() as client:
        logger.info("📱 Starting Mobile Client Flow")

        auth_resp = await client.post(
            f"{LARAVEL_URL}/login",
            json={
                "email": TEST_USER_EMAIL,
                "password": TEST_USER_PASSWORD,
                "device_fingerprint": f"e2e-{uuid.uuid4()}",
            },
        )
        if auth_resp.status_code != 200:
            logger.error(f"❌ Login Failed: {auth_resp.text}")
            raise Exception("Login failed")

        resp_data = auth_resp.json()
        token = resp_data.get("jwt")
        user_id = resp_data.get("user_id")
        headers = {"Authorization": f"Bearer {token}"}
        logger.info("✅ Logged in to Laravel")

        init_resp = await client.post(
            f"{LARAVEL_URL}/pair/init", json={"device_label": DEVICE_LABEL}, headers=headers
        )
        if init_resp.status_code != 200:
            logger.error(f"❌ Pairing Init Failed: {init_resp.text}")
            raise Exception("Pairing init failed")
        init_data = init_resp.json()
        pair_session_id = init_data.get("pair_session_id")
        logger.info(f"✅ Pairing initiated, session: {pair_session_id}")

        agent_signing_key = SigningKey.generate()
        agent_pubkey_b64 = agent_signing_key.verify_key.encode(encoder=Base64Encoder).decode("utf-8")
        pair_request = await client.post(
            f"{LARAVEL_URL}/pair/request",
            json={
                "device_name": DEVICE_LABEL,
                "hwid": f"HWID-{uuid.uuid4()}",
                "pubkey": agent_pubkey_b64,
            },
        )
        if pair_request.status_code != 200:
            logger.error(f"❌ Pairing Request Failed: {pair_request.text}")
            raise Exception("Pairing request failed")
        request_data = pair_request.json()
        pair_token = request_data.get("pair_token")
        device_id = request_data.get("device_id")
        if not pair_token or not device_id:
            raise Exception("Pairing request missing token or device_id")
        logger.info(f"✅ Pairing request ok, token: {pair_token[:20]}...")

        confirm_resp = await client.post(
            f"{LARAVEL_URL}/pair/confirm",
            json={"pair_token": pair_token, "pair_session_id": pair_session_id},
            headers=headers,
        )
        if confirm_resp.status_code != 200:
            logger.error(f"❌ Pairing Confirm Failed: {confirm_resp.text}")
            raise Exception("Pairing confirm failed")
        device_id = confirm_resp.json()["device_id"]
        logger.info(f"✅ Paired! Device ID: {device_id}")

        agent_token_resp = await client.post(f"{LARAVEL_URL}/agent/token", json={"pair_token": pair_token})
        if agent_token_resp.status_code != 200:
            logger.error(f"❌ Agent token failed: {agent_token_resp.text}")
            raise Exception("Agent token failed")
        agent_jwt = agent_token_resp.json().get("jwt")
        if not agent_jwt:
            raise Exception("Agent token response missing jwt")

        return token, device_id, user_id, agent_jwt, agent_signing_key


async def send_command_via_api(
    token: str,
    device_id: str,
    user_id: str,
    user_role: str,
    method: str,
    params: dict,
    two_factor_code: str | None = None,
) -> dict:
    async with httpx.AsyncClient() as client:
        headers = {"Authorization": f"Bearer {token}"}
        cmd_payload = {
            "device_id": device_id,
            "method": method,
            "params": params,
            "client_message_id": uuid.uuid4().hex,
            "sensitive": False,
            "user_id": user_id,
            "user_role": user_role,
            "attestation_status": "pass",
        }
        if two_factor_code:
            cmd_payload["two_factor_code"] = two_factor_code
        logger.info(f"🚀 Sending '{method}' Command via API...")
        resp = await client.post(f"{LARAVEL_URL}/commands", json=cmd_payload, headers=headers)
        result = resp.json()
        if resp.status_code in [200, 201]:
            logger.info(f"✅ Command Accepted: {result.get('status')} - ID: {result.get('command_id')}")
        else:
            logger.error(f"❌ Command Failed: {resp.text}")
        return result


async def poll_command(token: str, command_id: str, timeout: int) -> dict:
    async with httpx.AsyncClient() as client:
        headers = {"Authorization": f"Bearer {token}"}
        deadline = time.time() + timeout
        while time.time() < deadline:
            resp = await client.get(f"{LARAVEL_URL}/commands/{command_id}", headers=headers)
            if resp.status_code != 200:
                await asyncio.sleep(COMMAND_POLL_INTERVAL)
                continue
            payload = resp.json()
            state = payload.get("state")
            if state in ("completed", "failed", "expired"):
                return payload
            await asyncio.sleep(COMMAND_POLL_INTERVAL)
        return {"command_id": command_id, "state": "timeout"}


async def main() -> None:
    logger.info("=" * 60)
    logger.info("   QUOODLE END-TO-END VERIFICATION TEST")
    logger.info("=" * 60)

    try:
        jwt_token, device_id, user_id, agent_jwt, agent_signing_key = await run_mobile_api_flow()

        agent = AgentEmulator(device_id, agent_jwt, signing_key=agent_signing_key)

        if not await agent.register_pubkey_with_gateway():
            logger.error("❌ Cannot proceed without pubkey registration")
            return

        await agent.connect()
        await asyncio.sleep(2)

        if not agent.session_id:
            logger.error("❌ Agent failed to authenticate")
            await agent.close()
            return

        results = []
        screenshot_saved = None
        for entry in COMMAND_SUITE:
            method = entry["method"]
            params = entry.get("params", {})
            role = TEST_USER_ROLE
            two_factor_code = None
            if method == "screenshot":
                role = SCREENSHOT_USER_ROLE
                two_factor_code = SCREENSHOT_TWO_FACTOR_CODE or None
            cmd_result = await send_command_via_api(
                jwt_token,
                device_id,
                user_id,
                role,
                method,
                params,
                two_factor_code=two_factor_code,
            )
            command_id = cmd_result.get("command_id")
            if not command_id:
                results.append({
                    "method": method,
                    "state": "rejected",
                    "reason": cmd_result.get("reason"),
                })
                if method == "screenshot":
                    reason = cmd_result.get("reason")
                    if reason in ("role_not_allowed", "require_2fa", "invalid_2fa"):
                        logger.warning(
                            "Screenshot rejected by policy (%s). Set SCREENSHOT_USER_ROLE=analyst and "
                            "SCREENSHOT_TWO_FACTOR_CODE=<totp> for a 2FA-enabled user.",
                            reason,
                        )
                continue
            received = await agent.wait_for_command(command_id, timeout=COMMAND_TIMEOUT_SECONDS)
            if not received:
                logger.warning(f"⚠️ Agent did not receive command {command_id} in time")
            final = await poll_command(jwt_token, command_id, timeout=COMMAND_TIMEOUT_SECONDS)
            results.append({
                "method": method,
                "command_id": command_id,
                "state": final.get("state"),
                "received": received,
            })

            if method == "screenshot" and final.get("state") == "completed":
                details = (
                    (final.get("result") or {})
                    .get("data", {})
                    .get("details", {})
                )
                rel_path = details.get("relative_path") or details.get("path")
                if rel_path and rel_path.startswith(ALLOWED_ROOT.rstrip(os.sep) + os.sep):
                    rel_path = os.path.relpath(rel_path, ALLOWED_ROOT)
                if rel_path:
                    download = await send_command_via_api(
                        jwt_token,
                        device_id,
                        user_id,
                        TEST_USER_ROLE,
                        "download_file",
                        {"path": rel_path, "max_bytes": 5 * 1024 * 1024},
                    )
                    dl_id = download.get("command_id")
                    if dl_id:
                        await agent.wait_for_command(dl_id, timeout=COMMAND_TIMEOUT_SECONDS)
                        dl_final = await poll_command(jwt_token, dl_id, timeout=COMMAND_TIMEOUT_SECONDS)
                        dl_details = (
                            (dl_final.get("result") or {})
                            .get("data", {})
                            .get("details", {})
                        )
                        data_b64 = dl_details.get("data_b64")
                        if data_b64:
                            out_dir = ROOT / "logs" / "e2e" / "screenshots"
                            out_dir.mkdir(parents=True, exist_ok=True)
                            out_path = out_dir / f"screenshot_{command_id}.png"
                            out_path.write_bytes(base64.b64decode(data_b64))
                            screenshot_saved = str(out_path)
                            logger.info(f"🖼️ Screenshot saved to {out_path}")

        await agent.close()

        logger.info("=" * 60)
        logger.info("   E2E TEST SUMMARY")
        logger.info("=" * 60)
        logger.info(f"✅ Login: Success")
        logger.info(f"✅ Pairing: Success (Device: {device_id})")
        logger.info(f"✅ Agent Pubkey Registration: Success")
        logger.info(f"✅ WSS Authentication: {'Success' if agent.session_id else 'Failed'}")
        for item in results:
            status = "✅" if item.get("state") == "completed" else "⚠️"
            reason = item.get("reason")
            extra = f" reason={reason}" if reason else ""
            logger.info(
                f"{status} {item.get('method')}: state={item.get('state')} received={item.get('received')}{extra}"
            )
        if screenshot_saved:
            logger.info(f"🖼️ Screenshot file: {screenshot_saved}")
        logger.info("=" * 60)

    except Exception as e:
        logger.error(f"❌ E2E Test Failed: {e}")
        import traceback

        traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(main())
