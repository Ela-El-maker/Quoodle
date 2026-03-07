#!/usr/bin/env python3
"""
Quoodle Linux Privileged Daemon
Implements the Agent <-> Privileged Executor contract over UDS.
"""

import asyncio
import base64
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import signal
import socket
import struct
import subprocess
import tarfile
import time
import uuid
from typing import Any, Dict, List, Optional, Tuple

from nacl.exceptions import BadSignatureError
from nacl.signing import SigningKey, VerifyKey

# Configuration
SOCKET_PATH = os.getenv("QUOODLE_PRIV_SOCKET", "/run/quoodle/privileged.sock")
ALLOWED_ROOT = os.path.realpath(os.getenv("QUOODLE_ALLOWED_ROOT", "/var/lib/quoodle/data"))
STATE_DIR = os.getenv("QUOODLE_PRIV_STATE_DIR", "/var/lib/quoodle/privileged")
ARTIFACT_DIR = os.path.realpath(os.getenv("QUOODLE_ARTIFACT_DIR", os.path.join(ALLOWED_ROOT, "artifacts")))
AUDIT_LOG_PATH = os.path.join(STATE_DIR, "audit.log")

AGENT_UID = int(os.getenv("QUOODLE_AGENT_UID", "1000"))
AGENT_GID = int(os.getenv("QUOODLE_AGENT_GID", "1000"))
ALLOW_ANY_PEER = os.getenv("QUOODLE_ALLOW_ANY_PEER", "0") == "1"

AGENT_PUBKEY_B64 = os.getenv("QUOODLE_AGENT_PUBKEY_B64", "")
DAEMON_PRIVKEY_B64 = os.getenv("QUOODLE_DAEMON_PRIVKEY_B64", "")
DAEMON_KID = os.getenv("QUOODLE_DAEMON_KID", "daemon-default")

MAX_CLOCK_SKEW_SECONDS = int(os.getenv("QUOODLE_MAX_CLOCK_SKEW_SECONDS", "120"))
REJECT_OLDER_THAN_SECONDS = int(os.getenv("QUOODLE_REJECT_OLDER_THAN_SECONDS", "600"))
DEDUP_WINDOW_SECONDS = int(os.getenv("QUOODLE_DEDUP_WINDOW_SECONDS", "86400"))

SERVICE_NAME = os.getenv("QUOODLE_AGENT_SERVICE", "quoodle-agent")
AGENT_KEYS_DIR = os.getenv("QUOODLE_AGENT_KEYS_DIR", os.path.join(STATE_DIR, "keys"))
UPDATE_DIR = os.path.realpath(os.getenv("QUOODLE_UPDATE_DIR", "/var/lib/quoodle/updates"))
AGENT_BIN_PATH = os.path.realpath(os.getenv("QUOODLE_AGENT_BIN_PATH", "/opt/quoodle-agent/bin/quoodle-agent-linux"))
AGENT_BACKUP_DIR = os.path.realpath(os.getenv("QUOODLE_AGENT_BACKUP_DIR", os.path.join(UPDATE_DIR, "backups")))

# State persistence
STATE_PATH = os.path.join(STATE_DIR, "state.json")


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def now_ts() -> str:
    return dt.datetime.utcnow().replace(tzinfo=dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def canonicalize(data: Dict[str, Any]) -> str:
    return json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def strip_sig(payload: Dict[str, Any]) -> str:
    data = json.loads(json.dumps(payload))
    if "sig" in data and isinstance(data["sig"], dict):
        data["sig"]["sig"] = ""
    return canonicalize(data)


def parse_iso8601(ts: str) -> Optional[dt.datetime]:
    try:
        if ts.endswith("Z"):
            ts = ts.replace("Z", "+00:00")
        return dt.datetime.fromisoformat(ts)
    except Exception:
        return None


def base64_decode(data: str) -> bytes:
    return base64.b64decode(data.encode("utf-8"))


def base64_encode(data: bytes) -> str:
    return base64.b64encode(data).decode("utf-8")


def check_peer_credentials(sock: socket.socket) -> bool:
    if ALLOW_ANY_PEER:
        return True
    try:
        creds = sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3I"))
        _, uid, gid = struct.unpack("3I", creds)
        return uid == AGENT_UID and gid == AGENT_GID
    except Exception:
        return False


def resolve_under_root(rel_path: str) -> str:
    if rel_path is None:
        raise ValueError("path is required")
    if not isinstance(rel_path, str) or rel_path.strip() == "":
        raise ValueError("path must be string")
    if rel_path.startswith("/"):
        raise ValueError("absolute paths are not allowed")
    full_path = os.path.realpath(os.path.join(ALLOWED_ROOT, rel_path))
    if not full_path.startswith(ALLOWED_ROOT.rstrip(os.sep) + os.sep):
        raise ValueError("path escapes allowed root")
    return full_path


def resolve_under_dir(base_dir: str, rel_path: str) -> str:
    if rel_path is None:
        raise ValueError("path is required")
    if not isinstance(rel_path, str) or rel_path.strip() == "":
        raise ValueError("path must be string")
    if rel_path.startswith("/"):
        raise ValueError("absolute paths are not allowed")
    full_path = os.path.realpath(os.path.join(base_dir, rel_path))
    if not full_path.startswith(base_dir.rstrip(os.sep) + os.sep):
        raise ValueError("path escapes base dir")
    return full_path


def safe_open_for_write(path: str) -> None:
    parent = os.path.dirname(path)
    ensure_dir(parent)


def safe_extract_tar(tar: tarfile.TarFile, dest: str) -> None:
    base = os.path.realpath(dest)
    for member in tar.getmembers():
        target = os.path.realpath(os.path.join(base, member.name))
        if not target.startswith(base.rstrip(os.sep) + os.sep):
            raise RuntimeError("tar contains unsafe path")
    tar.extractall(dest)


class StateStore:
    def __init__(self, path: str) -> None:
        self.path = path
        self.data: Dict[str, Any] = {
            "seq": {},
            "idempotency": {},
            "quarantine": False,
            "input_disabled": {},
            "flags": {},
        }
        self.load()

    def load(self) -> None:
        try:
            if os.path.exists(self.path):
                with open(self.path, "r", encoding="utf-8") as f:
                    loaded = json.load(f)
                    if isinstance(loaded, dict):
                        self.data.update(loaded)
        except Exception:
            pass

    def save(self) -> None:
        ensure_dir(os.path.dirname(self.path))
        tmp = f"{self.path}.tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.data, f)
        os.replace(tmp, self.path)

    def purge_idempotency(self) -> None:
        now = time.time()
        keep: Dict[str, Any] = {}
        for key, value in self.data.get("idempotency", {}).items():
            ts = value.get("timestamp", 0)
            if now - ts <= DEDUP_WINDOW_SECONDS:
                keep[key] = value
        self.data["idempotency"] = keep

    def get_cached_response(self, request_id: str) -> Optional[Dict[str, Any]]:
        entry = self.data.get("idempotency", {}).get(request_id)
        if entry and isinstance(entry.get("response"), dict):
            return entry["response"]
        return None

    def cache_response(self, request_id: str, command_message_id: str, response: Dict[str, Any]) -> None:
        self.data.setdefault("idempotency", {})[request_id] = {
            "timestamp": time.time(),
            "command_message_id": command_message_id,
            "response": response,
        }
        self.purge_idempotency()
        self.save()

    def find_response_by_command_id(self, command_id: str) -> Optional[Dict[str, Any]]:
        for entry in self.data.get("idempotency", {}).values():
            if entry.get("command_message_id") == command_id:
                resp = entry.get("response")
                if isinstance(resp, dict):
                    return resp
        return None

    def update_seq(self, kid: str, seq: int) -> bool:
        last = int(self.data.get("seq", {}).get(kid, 0))
        if seq <= last:
            return False
        self.data.setdefault("seq", {})[kid] = seq
        self.save()
        return True

    def set_flag(self, name: str, value: Any) -> None:
        self.data.setdefault("flags", {})[name] = value
        self.save()

    def get_flag(self, name: str, default: Any = None) -> Any:
        return self.data.get("flags", {}).get(name, default)


STATE = StateStore(STATE_PATH)


def append_audit(entry: Dict[str, Any]) -> None:
    ensure_dir(os.path.dirname(AUDIT_LOG_PATH))
    with open(AUDIT_LOG_PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")


def build_error(request_id: str, err_type: str, message: str, code: int = 0, status: str = "failed") -> Dict[str, Any]:
    return {
        "request_id": request_id,
        "status": status,
        "exec_id": str(uuid.uuid4()),
        "timestamp": now_ts(),
        "error": {
            "type": err_type,
            "code": code,
            "message": message,
        },
        "result": None,
        "sig": {},
    }


def build_ok(request_id: str, result: Any) -> Dict[str, Any]:
    return {
        "request_id": request_id,
        "status": "ok",
        "exec_id": str(uuid.uuid4()),
        "timestamp": now_ts(),
        "error": None,
        "result": result,
        "sig": {},
    }


def sign_response(response: Dict[str, Any]) -> Dict[str, Any]:
    sig_block = {
        "alg": "Ed25519",
        "kid": DAEMON_KID,
        "canon": "JCS-v1",
        "signer": "daemon",
        "sig": "",
    }
    response["sig"] = sig_block
    if not DAEMON_PRIVKEY_B64:
        return response
    try:
        key = SigningKey(base64_decode(DAEMON_PRIVKEY_B64))
    except Exception:
        return response
    canonical = strip_sig(response)
    signature = key.sign(canonical.encode("utf-8")).signature
    response["sig"]["sig"] = base64_encode(signature)
    return response


def verify_signature(payload: Dict[str, Any]) -> Tuple[bool, str]:
    sig = payload.get("sig")
    if not isinstance(sig, dict):
        return False, "Missing sig"
    sig_b64 = sig.get("sig")
    if not sig_b64:
        return False, "Missing signature"
    if not AGENT_PUBKEY_B64:
        return False, "Missing agent public key"
    try:
        vk = VerifyKey(base64_decode(AGENT_PUBKEY_B64))
        canonical = strip_sig(payload)
        vk.verify(canonical.encode("utf-8"), base64_decode(sig_b64))
        return True, ""
    except BadSignatureError:
        return False, "Signature verification failed"
    except Exception as exc:
        return False, str(exc)


def run_command(cmd: List[str], env: Optional[Dict[str, str]] = None, timeout: int = 15) -> Tuple[int, str, str]:
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=timeout, text=True)
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except FileNotFoundError:
        return 1, "", "command not found"


def find_executable(name: str) -> Optional[str]:
    return shutil.which(name)


def active_sessions() -> List[Dict[str, Any]]:
    rc, out, _ = run_command(["loginctl", "list-sessions", "--no-legend"])
    if rc != 0:
        return []
    sessions: List[Dict[str, Any]] = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        session_id, uid, user = parts[0], parts[1], parts[2]
        rc2, info, _ = run_command([
            "loginctl",
            "show-session",
            session_id,
            "-p",
            "Active",
            "-p",
            "State",
            "-p",
            "Type",
            "-p",
            "Display",
            "-p",
            "IdleSinceHintUSec",
        ])
        if rc2 != 0:
            continue
        data = {"session": session_id, "uid": int(uid), "user": user}
        for row in info.splitlines():
            if "=" in row:
                key, value = row.split("=", 1)
                data[key] = value
        sessions.append(data)
    return sessions


def select_active_session() -> Optional[Dict[str, Any]]:
    sessions = active_sessions()
    for sess in sessions:
        if sess.get("Active", "no") == "yes" or sess.get("State") == "active":
            return sess
    return sessions[0] if sessions else None


def user_env(session: Dict[str, Any]) -> Dict[str, str]:
    uid = session["uid"]
    env = os.environ.copy()
    runtime_dir = f"/run/user/{uid}"
    env["XDG_RUNTIME_DIR"] = runtime_dir
    env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={runtime_dir}/bus"
    display = session.get("Display")
    if display:
        env["DISPLAY"] = display
    return env


def run_as_user(session: Dict[str, Any], cmd: List[str], timeout: int = 20) -> Tuple[int, str, str]:
    user = session["user"]
    base_cmd = []
    if find_executable("runuser"):
        base_cmd = ["runuser", "-u", user, "--"]
    elif find_executable("sudo"):
        base_cmd = ["sudo", "-u", user, "--"]
    else:
        return 1, "", "runuser/sudo not available"
    env = user_env(session)
    return run_command(base_cmd + cmd, env=env, timeout=timeout)


def list_processes(params: Dict[str, Any]) -> List[Dict[str, Any]]:
    limit = int(params.get("limit", 200))
    name_filter = params.get("name")
    user_filter = params.get("user")
    results = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/status", "r", encoding="utf-8") as f:
                status = f.read()
            name_match = re.search(r"^Name:\s+(.*)$", status, re.MULTILINE)
            uid_match = re.search(r"^Uid:\s+(\d+)", status, re.MULTILINE)
            name = name_match.group(1) if name_match else "unknown"
            uid = int(uid_match.group(1)) if uid_match else -1
            user = None
            try:
                import pwd

                user = pwd.getpwuid(uid).pw_name
            except Exception:
                user = str(uid)
            if name_filter and name_filter not in name:
                continue
            if user_filter and user_filter != user:
                continue
            cmdline = ""
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\x00", b" ").decode("utf-8", "ignore").strip()
            results.append({
                "pid": int(pid),
                "name": name,
                "user": user,
                "cmdline": cmdline,
            })
            if len(results) >= limit:
                break
        except Exception:
            continue
    return results


def list_services() -> List[Dict[str, Any]]:
    rc, out, _ = run_command(["systemctl", "list-units", "--type=service", "--all", "--no-legend", "--no-pager"])
    if rc != 0:
        return []
    services = []
    for line in out.splitlines():
        parts = line.split(None, 4)
        if len(parts) < 5:
            continue
        services.append({
            "unit": parts[0],
            "load": parts[1],
            "active": parts[2],
            "sub": parts[3],
            "description": parts[4],
        })
    return services


def list_mounts() -> List[Dict[str, Any]]:
    mounts = []
    with open("/proc/mounts", "r", encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 3:
                mounts.append({
                    "source": parts[0],
                    "target": parts[1],
                    "fstype": parts[2],
                })
    return mounts


def network_info() -> Dict[str, Any]:
    info: Dict[str, Any] = {"interfaces": [], "routes": []}
    if find_executable("ip"):
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
    if not info["interfaces"]:
        with open("/proc/net/dev", "r", encoding="utf-8") as f:
            lines = f.readlines()[2:]
        interfaces = []
        for line in lines:
            name, data = line.split(":", 1)
            interfaces.append({"name": name.strip(), "stats": data.split()})
        info["interfaces"] = interfaces
    return info


def list_connections(limit: int = 500) -> List[Dict[str, Any]]:
    if find_executable("ss"):
        rc, out, _ = run_command(["ss", "-tunapH"])
        if rc == 0:
            conns = []
            for line in out.splitlines():
                parts = line.split()
                if len(parts) < 5:
                    continue
                conns.append({
                    "state": parts[0],
                    "local": parts[3],
                    "remote": parts[4],
                    "process": " ".join(parts[5:]) if len(parts) > 5 else "",
                })
                if len(conns) >= limit:
                    break
            return conns
    return []


def get_users() -> List[Dict[str, Any]]:
    rc, out, _ = run_command(["who"])
    if rc != 0:
        return []
    users = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            users.append({
                "user": parts[0],
                "tty": parts[1],
                "since": " ".join(parts[2:4]) if len(parts) >= 4 else "",
            })
    return users


def get_sessions() -> List[Dict[str, Any]]:
    sessions = []
    for sess in active_sessions():
        sessions.append({
            "session": sess.get("session"),
            "user": sess.get("user"),
            "uid": sess.get("uid"),
            "active": sess.get("Active"),
            "state": sess.get("State"),
            "type": sess.get("Type"),
            "display": sess.get("Display"),
        })
    return sessions


def sysinfo() -> Dict[str, Any]:
    info: Dict[str, Any] = {}
    rc, out, _ = run_command(["uname", "-a"])
    if rc == 0:
        info["uname"] = out
    try:
        with open("/etc/os-release", "r", encoding="utf-8") as f:
            info["os_release"] = f.read()
    except Exception:
        info["os_release"] = ""
    try:
        with open("/proc/uptime", "r", encoding="utf-8") as f:
            uptime_raw = f.read().split()[0]
            info["uptime_seconds"] = int(float(uptime_raw))
    except Exception:
        info["uptime_seconds"] = None
    info["loadavg"] = {}
    try:
        with open("/proc/loadavg", "r", encoding="utf-8") as f:
            parts = f.read().split()
            info["loadavg"] = {"1m": parts[0], "5m": parts[1], "15m": parts[2]}
    except Exception:
        info["loadavg"] = {}
    return info


def env_fingerprint(session: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    fp = {
        "session_type": os.getenv("XDG_SESSION_TYPE", ""),
        "desktop": os.getenv("XDG_CURRENT_DESKTOP", ""),
        "session": os.getenv("DESKTOP_SESSION", ""),
    }
    if session:
        fp["active_user"] = session.get("user")
        fp["display"] = session.get("Display")
    return fp


def ensure_firewall_chain_iptables() -> None:
    if not find_executable("iptables"):
        return
    run_command(["iptables", "-N", "QUOODLE_OUT"])
    run_command(["iptables", "-N", "QUOODLE_IN"])
    run_command(["iptables", "-C", "OUTPUT", "-j", "QUOODLE_OUT"])
    run_command(["iptables", "-C", "INPUT", "-j", "QUOODLE_IN"])
    run_command(["iptables", "-I", "OUTPUT", "1", "-j", "QUOODLE_OUT"])
    run_command(["iptables", "-I", "INPUT", "1", "-j", "QUOODLE_IN"])


def iptables_block(outbound: bool, inbound: bool) -> None:
    if not find_executable("iptables"):
        return
    ensure_firewall_chain_iptables()
    run_command(["iptables", "-F", "QUOODLE_OUT"])
    run_command(["iptables", "-F", "QUOODLE_IN"])
    if outbound:
        run_command(["iptables", "-A", "QUOODLE_OUT", "-j", "DROP"])
    if inbound:
        run_command(["iptables", "-A", "QUOODLE_IN", "-j", "DROP"])


def iptables_allow() -> None:
    if not find_executable("iptables"):
        return
    run_command(["iptables", "-F", "QUOODLE_OUT"])
    run_command(["iptables", "-F", "QUOODLE_IN"])


def nft_block(outbound: bool, inbound: bool) -> None:
    if not find_executable("nft"):
        return
    run_command(["nft", "add", "table", "inet", "quoodle"])
    run_command([
        "nft",
        "add",
        "chain",
        "inet",
        "quoodle",
        "output",
        "{",
        "type",
        "filter",
        "hook",
        "output",
        "priority",
        "0",
        ";",
        "policy",
        "accept",
        ";",
        "}",
    ])
    run_command([
        "nft",
        "add",
        "chain",
        "inet",
        "quoodle",
        "input",
        "{",
        "type",
        "filter",
        "hook",
        "input",
        "priority",
        "0",
        ";",
        "policy",
        "accept",
        ";",
        "}",
    ])
    run_command(["nft", "flush", "chain", "inet", "quoodle", "output"])
    run_command(["nft", "flush", "chain", "inet", "quoodle", "input"])
    if outbound:
        run_command(["nft", "add", "rule", "inet", "quoodle", "output", "counter", "drop"])
    if inbound:
        run_command(["nft", "add", "rule", "inet", "quoodle", "input", "counter", "drop"])


def nft_allow() -> None:
    if not find_executable("nft"):
        return
    run_command(["nft", "flush", "chain", "inet", "quoodle", "output"])
    run_command(["nft", "flush", "chain", "inet", "quoodle", "input"])


def network_block(outbound: bool, inbound: bool) -> None:
    nft_block(outbound, inbound)
    iptables_block(outbound, inbound)


def network_allow() -> None:
    nft_allow()
    iptables_allow()


def capture_screenshot(session: Dict[str, Any]) -> str:
    ensure_dir(ARTIFACT_DIR)
    filename = f"screenshot-{int(time.time())}.png"
    path = os.path.join(ARTIFACT_DIR, filename)
    if session.get("Type") == "wayland" and find_executable("grim"):
        rc, _, err = run_as_user(session, ["grim", path])
        if rc != 0:
            raise RuntimeError(err or "grim failed")
        return path
    if find_executable("gnome-screenshot"):
        rc, _, err = run_as_user(session, ["gnome-screenshot", "-f", path])
        if rc != 0:
            raise RuntimeError(err or "gnome-screenshot failed")
        return path
    if find_executable("scrot"):
        rc, _, err = run_as_user(session, ["scrot", path])
        if rc != 0:
            raise RuntimeError(err or "scrot failed")
        return path
    if find_executable("import"):
        rc, _, err = run_as_user(session, ["import", "-window", "root", path])
        if rc != 0:
            raise RuntimeError(err or "import failed")
        return path
    raise RuntimeError("no screenshot tool available")


def xinput_devices(session: Dict[str, Any], scope: str) -> List[str]:
    rc, out, _ = run_as_user(session, ["xinput", "list"])
    if rc != 0:
        return []
    ids = []
    for line in out.splitlines():
        if "id=" not in line:
            continue
        name = line.strip()
        if scope == "mouse" and "mouse" not in name.lower() and "pointer" not in name.lower():
            continue
        if scope == "keyboard" and "keyboard" not in name.lower():
            continue
        match = re.search(r"id=(\d+)", line)
        if match:
            ids.append(match.group(1))
    return ids


def set_input_enabled(session: Dict[str, Any], enabled: bool, scope: str) -> List[str]:
    ids = xinput_devices(session, scope)
    if not ids:
        return []
    for dev_id in ids:
        cmd = ["xinput", "enable" if enabled else "disable", dev_id]
        run_as_user(session, cmd)
    return ids


def set_wallpaper(session: Dict[str, Any], image_path: str) -> None:
    uri = f"file://{image_path}"
    if find_executable("gsettings"):
        run_as_user(session, ["gsettings", "set", "org.gnome.desktop.background", "picture-uri", uri])
        run_as_user(session, ["gsettings", "set", "org.gnome.desktop.background", "picture-uri-dark", uri])
        return
    if find_executable("feh"):
        run_as_user(session, ["feh", "--bg-scale", image_path])
        return
    raise RuntimeError("no wallpaper tool available")


def create_wallpaper_from_message(message: str) -> str:
    ensure_dir(ARTIFACT_DIR)
    filename = f"wallpaper-{int(time.time())}.png"
    path = os.path.join(ARTIFACT_DIR, filename)
    if not find_executable("convert"):
        raise RuntimeError("ImageMagick convert not available")
    cmd = [
        "convert",
        "-size",
        "1920x1080",
        "xc:black",
        "-fill",
        "white",
        "-pointsize",
        "48",
        "-gravity",
        "center",
        "-annotate",
        "+0+0",
        message,
        path,
    ]
    rc, _, err = run_command(cmd)
    if rc != 0:
        raise RuntimeError(err or "convert failed")
    return path


def build_health() -> Dict[str, Any]:
    info = {
        "time": now_ts(),
        "pid": os.getpid(),
        "uptime_seconds": None,
        "loadavg": None,
    }
    try:
        with open("/proc/uptime", "r", encoding="utf-8") as f:
            uptime_raw = f.read().split()[0]
            info["uptime_seconds"] = int(float(uptime_raw))
    except Exception:
        pass
    try:
        with open("/proc/loadavg", "r", encoding="utf-8") as f:
            info["loadavg"] = f.read().split()[:3]
    except Exception:
        pass
    return info


def handle_capability(cap: str, params: Dict[str, Any], request: Dict[str, Any]) -> Dict[str, Any]:
    session = select_active_session()

    if cap == "CAP_LOCK_SESSION":
        count = 0
        for sess in active_sessions():
            rc, _, _ = run_command(["loginctl", "lock-session", sess["session"]])
            if rc == 0:
                count += 1
        return {"session_count_locked": count}

    if cap == "CAP_LOGOUT_SESSION":
        count = 0
        for sess in active_sessions():
            rc, _, _ = run_command(["loginctl", "terminate-session", sess["session"]])
            if rc == 0:
                count += 1
        return {"session_count_terminated": count}

    if cap == "CAP_REBOOT_SYSTEM":
        delay = int(params.get("delay_seconds", 0))
        if delay > 0:
            minutes = max(1, int(delay / 60))
            run_command(["shutdown", "-r", f"+{minutes}"])
        else:
            run_command(["systemctl", "reboot", "--no-wall"])
        return {"initiated": True}

    if cap == "CAP_SHUTDOWN_SYSTEM":
        delay = int(params.get("delay_seconds", 0))
        if delay > 0:
            minutes = max(1, int(delay / 60))
            run_command(["shutdown", "-h", f"+{minutes}"])
        else:
            run_command(["systemctl", "poweroff", "--no-wall"])
        return {"initiated": True}

    if cap == "CAP_INPUT_CONTROL":
        if not session:
            raise RuntimeError("no active session")
        enabled = bool(params.get("enabled", False))
        scope = params.get("scope", "all")
        ids = set_input_enabled(session, enabled, scope)
        if not enabled:
            STATE.data.setdefault("input_disabled", {})[session["session"]] = ids
            duration = int(params.get("duration_seconds", 0))
            if duration > 0:
                def _reenable() -> None:
                    try:
                        set_input_enabled(session, True, scope)
                    except Exception:
                        pass
                loop = asyncio.get_running_loop()
                loop.call_later(duration, _reenable)
        return {"enabled": enabled, "devices": ids}

    if cap == "CAP_SET_WALLPAPER":
        if not session:
            raise RuntimeError("no active session")
        image_url = params.get("image_url")
        message = params.get("message")
        path = None
        if image_url:
            if image_url.startswith("/"):
                path = resolve_under_root(os.path.relpath(image_url, ALLOWED_ROOT))
            else:
                path = resolve_under_root(image_url)
        else:
            if not message:
                raise RuntimeError("message or image_url required")
            path = create_wallpaper_from_message(message)
        set_wallpaper(session, path)
        return {"path": path}

    if cap == "CAP_SHOW_MESSAGE":
        if not session:
            raise RuntimeError("no active session")
        message = params.get("message", "")
        blocking = bool(params.get("blocking", False))
        severity = params.get("severity", "info")
        if blocking and find_executable("zenity"):
            run_as_user(session, ["zenity", "--info", f"--text={message}", f"--title={severity}"])
        elif find_executable("notify-send"):
            run_as_user(session, ["notify-send", severity, message])
        else:
            raise RuntimeError("no notification tool available")
        return {"delivered": True}

    if cap == "CAP_LOCK_AND_CAPTURE":
        if not session:
            raise RuntimeError("no active session")
        handle_capability("CAP_LOCK_SESSION", {}, request)
        path = capture_screenshot(session)
        return {"locked": True, "screenshot_path": path}

    if cap == "CAP_SYSINFO":
        return sysinfo()

    if cap == "CAP_LIST_PROCESSES":
        return {"processes": list_processes(params)}

    if cap == "CAP_GET_USERS":
        return {"users": get_users()}

    if cap == "CAP_GET_SESSIONS":
        return {"sessions": get_sessions()}

    if cap == "CAP_LIST_SERVICES":
        return {"services": list_services()}

    if cap == "CAP_NETWORK_INFO":
        return network_info()

    if cap == "CAP_LIST_MOUNTS":
        return {"mounts": list_mounts()}

    if cap == "CAP_ENV_FINGERPRINT":
        return env_fingerprint(session)

    if cap == "CAP_FS_LIST":
        path = resolve_under_root(params.get("path"))
        recursive = bool(params.get("recursive", False))
        limit = int(params.get("limit", 500))
        entries = []
        if recursive:
            for root, dirs, files in os.walk(path):
                for name in dirs + files:
                    full = os.path.join(root, name)
                    stat = os.stat(full)
                    entries.append({
                        "path": os.path.relpath(full, ALLOWED_ROOT),
                        "is_dir": os.path.isdir(full),
                        "size": int(stat.st_size),
                        "mtime": int(stat.st_mtime),
                    })
                    if len(entries) >= limit:
                        break
                if len(entries) >= limit:
                    break
        else:
            for entry in os.scandir(path):
                stat = entry.stat()
                entries.append({
                    "path": os.path.relpath(entry.path, ALLOWED_ROOT),
                    "is_dir": entry.is_dir(),
                    "size": int(stat.st_size),
                    "mtime": int(stat.st_mtime),
                })
                if len(entries) >= limit:
                    break
        return {"entries": entries}

    if cap == "CAP_FS_STAT":
        path = resolve_under_root(params.get("path"))
        stat = os.stat(path)
        return {
            "path": os.path.relpath(path, ALLOWED_ROOT),
            "size": int(stat.st_size),
            "mtime": int(stat.st_mtime),
            "mode": int(stat.st_mode),
        }

    if cap == "CAP_FS_READ":
        path = resolve_under_root(params.get("path"))
        max_bytes = int(params.get("max_bytes", 1024 * 1024))
        encoding = params.get("encoding", "utf8")
        with open(path, "rb") as f:
            data = f.read(max_bytes)
        if encoding == "base64":
            return {"data_b64": base64_encode(data)}
        return {"data": data.decode("utf-8", "replace")}

    if cap == "CAP_FS_SEARCH":
        path = resolve_under_root(params.get("path"))
        pattern = params.get("pattern", "")
        is_regex = bool(params.get("regex", False))
        limit = int(params.get("limit", 200))
        results = []
        if is_regex:
            try:
                regex = re.compile(pattern)
            except re.error:
                raise RuntimeError("invalid regex")
        else:
            regex = None
        for root, _, files in os.walk(path):
            for name in files:
                match = regex.search(name) if regex else (pattern in name)
                if match:
                    full = os.path.join(root, name)
                    results.append(os.path.relpath(full, ALLOWED_ROOT))
                    if len(results) >= limit:
                        break
            if len(results) >= limit:
                break
        return {"matches": results}

    if cap == "CAP_FS_HASH":
        path = resolve_under_root(params.get("path"))
        algo = params.get("algo", "sha256")
        h = hashlib.new(algo)
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return {"hash": h.hexdigest(), "algo": algo}

    if cap == "CAP_FS_DOWNLOAD":
        path = resolve_under_root(params.get("path"))
        max_bytes = int(params.get("max_bytes", 5 * 1024 * 1024))
        with open(path, "rb") as f:
            data = f.read(max_bytes)
        return {"data_b64": base64_encode(data), "size": len(data)}

    if cap == "CAP_FS_UPLOAD":
        dest = resolve_under_root(params.get("destination"))
        content_b64 = params.get("content_b64")
        artifact_id = params.get("artifact_id")
        safe_open_for_write(dest)
        if content_b64:
            with open(dest, "wb") as f:
                f.write(base64_decode(content_b64))
            return {"written": True, "path": os.path.relpath(dest, ALLOWED_ROOT)}
        if artifact_id:
            candidate = os.path.join(ARTIFACT_DIR, artifact_id)
            if not os.path.exists(candidate):
                candidate = os.path.join(ARTIFACT_DIR, f"{artifact_id}.bin")
            if not os.path.exists(candidate):
                raise RuntimeError("artifact not found")
            shutil.copyfile(candidate, dest)
            return {"written": True, "path": os.path.relpath(dest, ALLOWED_ROOT)}
        raise RuntimeError("content_b64 or artifact_id required")

    if cap == "CAP_FS_DELETE":
        path = resolve_under_root(params.get("path"))
        if os.path.isdir(path):
            raise RuntimeError("refusing to delete directory")
        os.remove(path)
        return {"deleted": True}

    if cap == "CAP_FS_MOVE":
        src = resolve_under_root(params.get("src"))
        dest = resolve_under_root(params.get("dest"))
        safe_open_for_write(dest)
        shutil.move(src, dest)
        return {"moved": True, "dest": os.path.relpath(dest, ALLOWED_ROOT)}

    if cap == "CAP_SCREENSHOT":
        if not session:
            raise RuntimeError("no active session")
        path = capture_screenshot(session)
        rel_path = None
        artifact_id = os.path.basename(path)
        if path.startswith(ALLOWED_ROOT.rstrip(os.sep) + os.sep):
            rel_path = os.path.relpath(path, ALLOWED_ROOT)
        sha256 = None
        try:
            h = hashlib.sha256()
            with open(path, "rb") as f:
                for chunk in iter(lambda: f.read(65536), b""):
                    h.update(chunk)
            sha256 = h.hexdigest()
        except Exception:
            sha256 = None
        return {
            "path": path,
            "relative_path": rel_path,
            "artifact_id": artifact_id,
            "sha256": sha256,
        }

    if cap == "CAP_ACTIVE_WINDOW":
        if not session:
            raise RuntimeError("no active session")
        rc, out, _ = run_as_user(session, ["xprop", "-root", "_NET_ACTIVE_WINDOW"])
        if rc != 0 or "0x" not in out:
            raise RuntimeError("unable to get active window")
        win_id = out.split()[-1]
        rc, out, _ = run_as_user(session, ["xprop", "-id", win_id, "_NET_WM_NAME"])
        return {"window_id": win_id, "title": out}

    if cap == "CAP_IDLE_TIME":
        if not session:
            raise RuntimeError("no active session")
        if find_executable("xprintidle"):
            rc, out, _ = run_as_user(session, ["xprintidle"])
            if rc == 0 and out.isdigit():
                return {"idle_ms": int(out)}
        idle_usec = session.get("IdleSinceHintUSec")
        if idle_usec and idle_usec.isdigit():
            idle_ms = int(int(idle_usec) / 1000)
            return {"idle_ms": idle_ms}
        raise RuntimeError("idle time unavailable")

    if cap == "CAP_TERMINATE_PROCESS":
        pid = int(params.get("pid", 0))
        sig = int(params.get("signal", 9))
        os.kill(pid, sig)
        return {"killed": True}

    if cap == "CAP_PAUSE_PROCESS":
        pid = int(params.get("pid", 0))
        os.kill(pid, signal.SIGSTOP)
        return {"paused": True}

    if cap == "CAP_RESUME_PROCESS":
        pid = int(params.get("pid", 0))
        os.kill(pid, signal.SIGCONT)
        return {"resumed": True}

    if cap == "CAP_SERVICE_START":
        unit = params.get("unit")
        rc, _, err = run_command(["systemctl", "start", unit])
        if rc != 0:
            raise RuntimeError(err or "systemctl start failed")
        return {"started": True}

    if cap == "CAP_SERVICE_STOP":
        unit = params.get("unit")
        rc, _, err = run_command(["systemctl", "stop", unit])
        if rc != 0:
            raise RuntimeError(err or "systemctl stop failed")
        return {"stopped": True}

    if cap == "CAP_SERVICE_RESTART":
        unit = params.get("unit")
        rc, _, err = run_command(["systemctl", "restart", unit])
        if rc != 0:
            raise RuntimeError(err or "systemctl restart failed")
        return {"restarted": True}

    if cap == "CAP_NETWORK_DISCONNECT":
        network_block(outbound=True, inbound=True)
        STATE.data["quarantine"] = True
        STATE.save()
        return {"isolated": True}

    if cap == "CAP_NETWORK_RECONNECT":
        network_allow()
        STATE.data["quarantine"] = False
        STATE.save()
        return {"isolated": False}

    if cap == "CAP_NETWORK_ISOLATION":
        enabled = bool(params.get("enabled", True))
        if enabled:
            network_block(outbound=True, inbound=True)
            STATE.data["quarantine"] = True
        else:
            network_allow()
            STATE.data["quarantine"] = False
        STATE.save()
        return {"isolated": enabled}

    if cap == "CAP_BLOCK_OUTBOUND":
        network_block(outbound=True, inbound=False)
        return {"outbound_blocked": True}

    if cap == "CAP_ALLOW_OUTBOUND":
        network_allow()
        return {"outbound_blocked": False}

    if cap == "CAP_LIST_CONNECTIONS":
        return {"connections": list_connections(int(params.get("limit", 200)))}

    if cap == "CAP_ROTATE_AGENT_KEYS":
        ensure_dir(AGENT_KEYS_DIR)
        sk = SigningKey.generate()
        pk = sk.verify_key
        priv_b64 = base64_encode(sk.encode())
        pub_b64 = base64_encode(pk.encode())
        kid = hashlib.sha256(pk.encode()).hexdigest()[:12]
        priv_path = os.path.join(AGENT_KEYS_DIR, f"agent-{kid}.key")
        pub_path = os.path.join(AGENT_KEYS_DIR, f"agent-{kid}.pub")
        with open(priv_path, "w", encoding="utf-8") as f:
            f.write(priv_b64)
        with open(pub_path, "w", encoding="utf-8") as f:
            f.write(pub_b64)
        return {"kid": kid, "public_key_b64": pub_b64, "private_key_b64": priv_b64}

    if cap == "CAP_REVOKE_DEVICE":
        STATE.set_flag("revoked", True)
        run_command(["systemctl", "stop", SERVICE_NAME])
        return {"revoked": True}

    if cap == "CAP_FORCE_REPAIR":
        rc, _, err = run_command(["systemctl", "restart", SERVICE_NAME])
        if rc != 0:
            raise RuntimeError(err or "restart failed")
        return {"restarted": True}

    if cap == "CAP_INVALIDATE_SESSIONS":
        scope = params.get("scope", "device")
        count = 0
        for sess in active_sessions():
            if scope in ("device", "all") or (scope == "user" and sess.get("user") == params.get("user")):
                rc, _, _ = run_command(["loginctl", "terminate-session", sess["session"]])
                if rc == 0:
                    count += 1
        return {"terminated": count}

    if cap == "CAP_ATTEST":
        if STATE.get_flag("attestation_fail", False):
            raise RuntimeError("attestation failed by policy")
        measurements = {
            "boot_id": open("/proc/sys/kernel/random/boot_id", "r", encoding="utf-8").read().strip(),
            "machine_id": open("/etc/machine-id", "r", encoding="utf-8").read().strip(),
            "kernel": run_command(["uname", "-r"])[1],
            "cmdline_hash": hashlib.sha256(open("/proc/cmdline", "rb").read()).hexdigest(),
        }
        return {"measurements": measurements}

    if cap == "CAP_FAIL_ATTESTATION":
        STATE.set_flag("attestation_fail", True)
        return {"attestation_fail": True}

    if cap == "CAP_ENTER_QUARANTINE":
        STATE.set_flag("quarantine", True)
        network_block(outbound=True, inbound=True)
        return {"quarantined": True}

    if cap == "CAP_EXIT_QUARANTINE":
        STATE.set_flag("quarantine", False)
        network_allow()
        return {"quarantined": False}

    if cap == "CAP_POLICY_PROBE":
        return {"policy_hash": STATE.get_flag("policy_hash", "unknown")}

    if cap == "CAP_GET_COMMAND_LOG" or cap == "CAP_GET_AUDIT_TRAIL":
        limit = int(params.get("limit", 200))
        entries = []
        if os.path.exists(AUDIT_LOG_PATH):
            with open(AUDIT_LOG_PATH, "r", encoding="utf-8") as f:
                for line in f.readlines()[-limit:]:
                    try:
                        entries.append(json.loads(line))
                    except Exception:
                        continue
        return {"entries": entries}

    if cap == "CAP_EXPORT_ARTIFACTS":
        ensure_dir(ARTIFACT_DIR)
        bundle = os.path.join(ARTIFACT_DIR, f"artifacts-{int(time.time())}.tar.gz")
        with tarfile.open(bundle, "w:gz") as tar:
            tar.add(ARTIFACT_DIR, arcname="artifacts")
        return {"bundle": bundle}

    if cap == "CAP_VERIFY_SIGNATURE":
        artifact_id = params.get("artifact_id")
        signature = params.get("signature")
        public_key = params.get("public_key")
        result = {"verified": False}
        if artifact_id:
            candidate = os.path.join(ARTIFACT_DIR, artifact_id)
            if not os.path.exists(candidate):
                candidate = os.path.join(ARTIFACT_DIR, f"{artifact_id}.bin")
            if not os.path.exists(candidate):
                raise RuntimeError("artifact not found")
            data = open(candidate, "rb").read()
            result["hash"] = hashlib.sha256(data).hexdigest()
        if signature and public_key:
            vk = VerifyKey(base64_decode(public_key))
            payload = result.get("hash", "").encode("utf-8")
            try:
                vk.verify(payload, base64_decode(signature))
                result["verified"] = True
            except BadSignatureError:
                result["verified"] = False
        return result

    if cap == "CAP_REPLAY_REQUEST":
        cmd_id = params.get("command_id")
        if not cmd_id:
            raise RuntimeError("command_id required")
        resp = STATE.find_response_by_command_id(cmd_id)
        if not resp:
            raise RuntimeError("no cached response")
        return {"response": resp}

    if cap == "CAP_PANIC_DISABLE_AGENT":
        duration = int(params.get("duration_seconds", 0))
        run_command(["systemctl", "stop", SERVICE_NAME])
        if duration > 0:
            loop = asyncio.get_running_loop()

            def _restart() -> None:
                run_command(["systemctl", "start", SERVICE_NAME])

            loop.call_later(duration, _restart)
        return {"disabled": True, "duration_seconds": duration}

    if cap == "CAP_REVOKE_ALL_KEYS":
        if os.path.isdir(AGENT_KEYS_DIR):
            for name in os.listdir(AGENT_KEYS_DIR):
                os.remove(os.path.join(AGENT_KEYS_DIR, name))
        return {"revoked": True}

    if cap == "CAP_RESTORE_DEFAULTS":
        STATE.data = {"seq": {}, "idempotency": {}, "quarantine": False, "input_disabled": {}, "flags": {}}
        STATE.save()
        network_allow()
        return {"restored": True}

    if cap == "CAP_UNLOCK_ALL":
        for sess in active_sessions():
            run_command(["loginctl", "unlock-session", sess["session"]])
        if session:
            set_input_enabled(session, True, "all")
        return {"unlocked": True}

    if cap == "CAP_HEALTH_CHECK":
        return build_health()

    if cap == "CAP_POLICY_SET":
        policy_hash = params.get("policy_hash", "")
        STATE.set_flag("policy_hash", policy_hash)
        return {"applied": True, "policy_hash": policy_hash}

    if cap == "CAP_DISCOVERY":
        return {"supported_caps": sorted(SUPPORTED_CAPABILITIES), "attestation_methods": ["basic"]} 

    if cap == "CAP_COLLECT_LOGS":
        lines = int(params.get("lines", 200))
        if find_executable("journalctl"):
            rc, out, _ = run_command(["journalctl", "-n", str(lines), "--no-pager"])
            return {"logs": out}
        log_path = "/var/log/syslog"
        if os.path.exists(log_path):
            with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
                return {"logs": "".join(f.readlines()[-lines:])}
        return {"logs": ""}

    if cap == "CAP_UPDATE_AGENT":
        version = params.get("version")
        if not version:
            raise RuntimeError("version required")
        reboot_after = bool(params.get("reboot_after", False))

        ensure_dir(UPDATE_DIR)
        candidates = [
            f"quoodle-agent-linux-{version}.tar.gz",
            f"quoodle-agent-linux-{version}.tgz",
            f"{version}.tar.gz",
            f"{version}.tgz",
            f"quoodle-agent-linux-{version}",
        ]
        bundle_path = None
        for name in candidates:
            candidate = resolve_under_dir(UPDATE_DIR, name)
            if os.path.exists(candidate):
                bundle_path = candidate
                break
        if not bundle_path:
            raise RuntimeError("update bundle not found")

        sha_candidates = [f"{bundle_path}.sha256", f"{bundle_path}.sha256sum"]
        for sha_path in sha_candidates:
            if os.path.exists(sha_path):
                with open(sha_path, "r", encoding="utf-8") as f:
                    expected = f.read().strip().split()[0]
                if expected:
                    h = hashlib.sha256()
                    with open(bundle_path, "rb") as f:
                        for chunk in iter(lambda: f.read(65536), b""):
                            h.update(chunk)
                    if h.hexdigest() != expected:
                        raise RuntimeError("bundle checksum mismatch")
                break

        staged_dir = resolve_under_dir(UPDATE_DIR, f"staging-{version}-{int(time.time())}")
        ensure_dir(staged_dir)
        new_binary = None
        if bundle_path.endswith((".tar.gz", ".tgz")):
            with tarfile.open(bundle_path, "r:*") as tar:
                safe_extract_tar(tar, staged_dir)
            for root, _, files in os.walk(staged_dir):
                if "quoodle-agent-linux" in files:
                    new_binary = os.path.join(root, "quoodle-agent-linux")
                    break
        else:
            new_binary = bundle_path

        if not new_binary or not os.path.exists(new_binary):
            raise RuntimeError("agent binary not found in bundle")

        rc, _, err = run_command(["systemctl", "stop", SERVICE_NAME])
        if rc != 0:
            raise RuntimeError(err or "failed to stop agent service")

        ensure_dir(os.path.dirname(AGENT_BIN_PATH))
        if os.path.exists(AGENT_BIN_PATH):
            ensure_dir(AGENT_BACKUP_DIR)
            backup_path = os.path.join(
                AGENT_BACKUP_DIR, f"{os.path.basename(AGENT_BIN_PATH)}.{int(time.time())}.bak"
            )
            shutil.copy2(AGENT_BIN_PATH, backup_path)

        shutil.copy2(new_binary, AGENT_BIN_PATH)
        os.chmod(AGENT_BIN_PATH, 0o755)

        run_command(["systemctl", "daemon-reload"])
        rc, _, err = run_command(["systemctl", "start", SERVICE_NAME])
        if rc != 0:
            raise RuntimeError(err or "failed to start agent service")

        if reboot_after:
            run_command(["systemctl", "reboot", "--no-wall"])

        return {
            "updated": True,
            "version": version,
            "bundle": bundle_path,
            "binary_path": AGENT_BIN_PATH,
            "reboot_scheduled": reboot_after,
        }

    raise RuntimeError("unsupported capability")


SUPPORTED_CAPABILITIES = [
    "CAP_LOCK_SESSION",
    "CAP_LOGOUT_SESSION",
    "CAP_REBOOT_SYSTEM",
    "CAP_SHUTDOWN_SYSTEM",
    "CAP_INPUT_CONTROL",
    "CAP_SET_WALLPAPER",
    "CAP_SHOW_MESSAGE",
    "CAP_LOCK_AND_CAPTURE",
    "CAP_SYSINFO",
    "CAP_LIST_PROCESSES",
    "CAP_GET_USERS",
    "CAP_GET_SESSIONS",
    "CAP_LIST_SERVICES",
    "CAP_NETWORK_INFO",
    "CAP_LIST_MOUNTS",
    "CAP_ENV_FINGERPRINT",
    "CAP_FS_LIST",
    "CAP_FS_STAT",
    "CAP_FS_READ",
    "CAP_FS_SEARCH",
    "CAP_FS_HASH",
    "CAP_FS_DOWNLOAD",
    "CAP_FS_UPLOAD",
    "CAP_FS_DELETE",
    "CAP_FS_MOVE",
    "CAP_SCREENSHOT",
    "CAP_ACTIVE_WINDOW",
    "CAP_IDLE_TIME",
    "CAP_TERMINATE_PROCESS",
    "CAP_PAUSE_PROCESS",
    "CAP_RESUME_PROCESS",
    "CAP_SERVICE_START",
    "CAP_SERVICE_STOP",
    "CAP_SERVICE_RESTART",
    "CAP_NETWORK_DISCONNECT",
    "CAP_NETWORK_RECONNECT",
    "CAP_BLOCK_OUTBOUND",
    "CAP_ALLOW_OUTBOUND",
    "CAP_NETWORK_ISOLATION",
    "CAP_LIST_CONNECTIONS",
    "CAP_ROTATE_AGENT_KEYS",
    "CAP_REVOKE_DEVICE",
    "CAP_FORCE_REPAIR",
    "CAP_INVALIDATE_SESSIONS",
    "CAP_ATTEST",
    "CAP_FAIL_ATTESTATION",
    "CAP_ENTER_QUARANTINE",
    "CAP_EXIT_QUARANTINE",
    "CAP_POLICY_PROBE",
    "CAP_GET_COMMAND_LOG",
    "CAP_GET_AUDIT_TRAIL",
    "CAP_EXPORT_ARTIFACTS",
    "CAP_VERIFY_SIGNATURE",
    "CAP_REPLAY_REQUEST",
    "CAP_PANIC_DISABLE_AGENT",
    "CAP_REVOKE_ALL_KEYS",
    "CAP_RESTORE_DEFAULTS",
    "CAP_UNLOCK_ALL",
    "CAP_HEALTH_CHECK",
    "CAP_POLICY_SET",
    "CAP_DISCOVERY",
    "CAP_COLLECT_LOGS",
    "CAP_UPDATE_AGENT",
]


def validate_request(payload: Dict[str, Any]) -> Tuple[bool, str]:
    required = [
        "request_id",
        "timestamp",
        "capability",
        "params",
        "agent_sequence",
        "policy_hash",
        "command_message_id",
        "sig",
    ]
    for field in required:
        if field not in payload:
            return False, f"missing {field}"
    return True, ""


def check_timestamp(ts: str) -> Tuple[bool, str]:
    parsed = parse_iso8601(ts)
    if not parsed:
        return False, "invalid timestamp"
    now = dt.datetime.now(dt.timezone.utc)
    delta = abs((now - parsed).total_seconds())
    if delta > REJECT_OLDER_THAN_SECONDS:
        return False, "timestamp too old"
    if delta > MAX_CLOCK_SKEW_SECONDS:
        return False, "clock skew too large"
    return True, ""


def kid_from_sig(payload: Dict[str, Any]) -> str:
    sig = payload.get("sig")
    if isinstance(sig, dict) and sig.get("kid"):
        return str(sig.get("kid"))
    return "unknown"


async def read_frame(reader: asyncio.StreamReader) -> Optional[str]:
    try:
        length_bytes = await reader.readexactly(4)
    except Exception:
        return None
    length = struct.unpack(">I", length_bytes)[0]
    if length == 0 or length > 1024 * 1024:
        return None
    data = await reader.readexactly(length)
    return data.decode("utf-8")


async def handle_connection(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    sock = writer.get_extra_info("socket")
    if not check_peer_credentials(sock):
        writer.close()
        await writer.wait_closed()
        return

    message_text = await read_frame(reader)
    if not message_text:
        writer.close()
        await writer.wait_closed()
        return

    try:
        payload = json.loads(message_text)
    except Exception:
        response = build_error("unknown", "ERR_SCHEMA_INVALID", "invalid json")
        response = sign_response(response)
        await send_response(writer, response)
        return

    valid, reason = validate_request(payload)
    if not valid:
        response = build_error(payload.get("request_id", "unknown"), "ERR_SCHEMA_INVALID", reason)
        response = sign_response(response)
        await send_response(writer, response)
        return

    request_id = payload.get("request_id")
    command_message_id = payload.get("command_message_id")

    cached = STATE.get_cached_response(request_id)
    if cached:
        await send_response(writer, cached)
        return

    ok, reason = check_timestamp(payload.get("timestamp"))
    if not ok:
        response = build_error(request_id, "ERR_SCHEMA_INVALID", reason)
        response = sign_response(response)
        STATE.cache_response(request_id, command_message_id, response)
        await send_response(writer, response)
        return

    sig_ok, sig_reason = verify_signature(payload)
    if not sig_ok:
        response = build_error(request_id, "ERR_SIG_INVALID", sig_reason)
        response = sign_response(response)
        STATE.cache_response(request_id, command_message_id, response)
        await send_response(writer, response)
        return

    kid = kid_from_sig(payload)
    seq = int(payload.get("agent_sequence", 0))
    if not STATE.update_seq(kid, seq):
        response = build_error(request_id, "ERR_REPLAY_DETECTED", "sequence replay detected")
        response = sign_response(response)
        STATE.cache_response(request_id, command_message_id, response)
        await send_response(writer, response)
        return

    capability = payload.get("capability")
    params = payload.get("params") or {}

    try:
        result = handle_capability(capability, params, payload)
        response = build_ok(request_id, result)
    except Exception as exc:
        response = build_error(request_id, "ERR_EXECUTION_FAILED", str(exc))

    response = sign_response(response)
    STATE.cache_response(request_id, command_message_id, response)

    append_audit({
        "timestamp": now_ts(),
        "request_id": request_id,
        "command_message_id": command_message_id,
        "capability": capability,
        "status": response.get("status"),
        "error": response.get("error"),
    })

    await send_response(writer, response)


async def send_response(writer: asyncio.StreamWriter, response: Dict[str, Any]) -> None:
    payload = json.dumps(response).encode("utf-8")
    length_bytes = struct.pack(">I", len(payload))
    writer.write(length_bytes + payload)
    await writer.drain()
    writer.close()
    await writer.wait_closed()


async def main():
    ensure_dir(os.path.dirname(SOCKET_PATH))
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    server = await asyncio.start_unix_server(handle_connection, SOCKET_PATH)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
