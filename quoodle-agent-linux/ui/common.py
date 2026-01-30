import base64
import json
import os
import socket
import subprocess
import time
from pathlib import Path
from typing import Dict, List, Tuple


DEFAULT_SECRETS = "/etc/quoodle/secrets.env"
DEFAULT_STATE_DIRS = [
    "/var/lib/quoodle-agent/state",
    "/var/lib/quoodle/agent",
]
DEFAULT_PRIV_STATE_DIRS = [
    "/var/lib/quoodle/privileged",
]

CAP_METADATA = {
    "CAP_LOCK_SESSION": ("low", "Lock current user session"),
    "CAP_LOGOUT_SESSION": ("medium", "Log out active user session"),
    "CAP_REBOOT_SYSTEM": ("high", "Reboot the device"),
    "CAP_SHUTDOWN_SYSTEM": ("high", "Shutdown the device"),
    "CAP_INPUT_CONTROL": ("medium", "Disable or enable local input"),
    "CAP_SET_WALLPAPER": ("low", "Set desktop wallpaper"),
    "CAP_SHOW_MESSAGE": ("low", "Display a user message"),
    "CAP_LOCK_AND_CAPTURE": ("high", "Lock screen then capture evidence"),
    "CAP_SYSINFO": ("low", "Collect system information"),
    "CAP_LIST_PROCESSES": ("medium", "List running processes"),
    "CAP_TERMINATE_PROCESS": ("high", "Terminate a process"),
    "CAP_LIST_SERVICES": ("medium", "List system services"),
    "CAP_SERVICE_RESTART": ("high", "Restart a system service"),
    "CAP_NETWORK_INFO": ("low", "Collect network info"),
    "CAP_NETWORK_ISOLATION": ("critical", "Quarantine network access"),
    "CAP_BLOCK_OUTBOUND": ("high", "Block outbound traffic"),
    "CAP_ALLOW_OUTBOUND": ("medium", "Allow outbound traffic"),
    "CAP_ATTEST": ("medium", "Run attestation"),
    "CAP_FAIL_ATTESTATION": ("critical", "Force attestation failure"),
    "CAP_ENTER_QUARANTINE": ("critical", "Place device in quarantine"),
    "CAP_EXIT_QUARANTINE": ("high", "Release device from quarantine"),
    "CAP_UPDATE_AGENT": ("high", "Update agent binary"),
    "CAP_EXPORT_ARTIFACTS": ("medium", "Export evidence artifacts"),
}


def read_env_file(path: str) -> Dict[str, str]:
    env: Dict[str, str] = {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, val = line.split("=", 1)
                env[key.strip()] = val.strip()
    except FileNotFoundError:
        pass
    return env


def merged_env(secrets_file: str = DEFAULT_SECRETS) -> Dict[str, str]:
    env = read_env_file(secrets_file)
    for k, v in os.environ.items():
        if v:
            env[k] = v
    return env


def get_state_dir(env: Dict[str, str]) -> str:
    env_dir = env.get("QUOODLE_AGENT_STATE_DIR")
    if env_dir:
        return env_dir
    for candidate in DEFAULT_STATE_DIRS:
        if os.path.isdir(candidate):
            return candidate
    return DEFAULT_STATE_DIRS[0]


def get_priv_state_dir(env: Dict[str, str]) -> str:
    env_dir = env.get("QUOODLE_PRIV_STATE_DIR")
    if env_dir:
        return env_dir
    for candidate in DEFAULT_PRIV_STATE_DIRS:
        if os.path.isdir(candidate):
            return candidate
    return DEFAULT_PRIV_STATE_DIRS[0]


def read_json(path: str) -> Dict:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def mask(value: str, keep: int = 6) -> str:
    if not value:
        return "-"
    if len(value) <= keep:
        return "*" * len(value)
    return value[:keep] + "..." + value[-4:]


def check_systemctl(service: str) -> str:
    try:
        result = subprocess.run(
            ["systemctl", "is-active", service],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return result.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def journal_tail(units: List[str], lines: int = 200) -> str:
    cmd = ["journalctl"]
    for unit in units:
        cmd.extend(["-u", unit])
    cmd.extend(["-n", str(lines), "--no-pager"])
    try:
        result = subprocess.run(cmd, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return result.stdout.strip()
    except Exception as exc:
        return f"journalctl error: {exc}"


def load_machine_id() -> str:
    for path in ("/etc/machine-id", "/var/lib/dbus/machine-id"):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read().strip()
        except FileNotFoundError:
            continue
    return ""


def attestation_hash() -> Tuple[str, str]:
    machine_id = load_machine_id()
    if not machine_id:
        return "-", "-"
    digest = base64.b64encode(
        __import__("hashlib").sha256(machine_id.encode("utf-8")).digest()
    ).decode("utf-8")
    return machine_id, digest


def validate_b64(value: str, min_len: int = 16) -> str:
    if not value:
        return "missing"
    try:
        raw = base64.b64decode(value.encode("utf-8"))
        if len(raw) < min_len:
            return "invalid"
        return "ok"
    except Exception:
        return "invalid"


def load_capabilities() -> List[str]:
    try:
        import importlib.util

        path = Path(__file__).resolve().parents[1] / "privileged_daemon.py"
        spec = importlib.util.spec_from_file_location("privileged_daemon", path)
        if spec and spec.loader:
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)  # type: ignore[arg-type]
            caps = getattr(mod, "SUPPORTED_CAPABILITIES", [])
            if isinstance(caps, list):
                return caps
    except Exception:
        pass
    return [
        "CAP_LOCK_SESSION",
        "CAP_SYSINFO",
        "CAP_LIST_PROCESSES",
        "CAP_ATTEST",
        "CAP_UPDATE_AGENT",
    ]


def capabilities_with_meta(caps: List[str]) -> List[Tuple[str, str, str]]:
    rows = []
    for cap in sorted(caps):
        meta = CAP_METADATA.get(cap, ("unknown", ""))
        rows.append((cap, meta[0], meta[1]))
    return rows


def send_notification(title: str, body: str, urgency: str = "normal") -> None:
    try:
        subprocess.run(
            ["notify-send", "-u", urgency, title, body],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def state_snapshot(secrets_file: str = DEFAULT_SECRETS) -> Dict[str, str]:
    env = merged_env(secrets_file)
    state_dir = get_state_dir(env)
    state_path = os.path.join(state_dir, "state.json")
    state = read_json(state_path)
    outbox = read_json(os.path.join(state_dir, "outbox.json"))
    priv_state_dir = get_priv_state_dir(env)
    priv_state = read_json(os.path.join(priv_state_dir, "state.json"))
    agent_status = check_systemctl("quoodle-agent")
    priv_status = check_systemctl("quoodle-privileged")
    policy_hash = state.get("policy_hash", "-")
    sequence = state.get("sequence", "-")
    last_delivery = state.get("last_delivery_id", "-")
    processed = state.get("processed_commands", [])
    outbox_items = outbox.get("items", []) if isinstance(outbox, dict) else []
    mtime = "-"
    try:
        mtime = time.strftime(
            "%Y-%m-%d %H:%M:%S",
            time.localtime(os.path.getmtime(os.path.join(state_dir, "state.json"))),
        )
    except Exception:
        pass

    return {
        "device_id": env.get("QUOODLE_DEVICE_ID", "-"),
        "ws_url": env.get("QUOODLE_WS_URL", "-"),
        "agent_jwt": env.get("QUOODLE_AGENT_JWT", ""),
        "state_dir": state_dir,
        "agent_status": agent_status,
        "priv_status": priv_status,
        "policy_hash": policy_hash,
        "sequence": str(sequence),
        "last_delivery": last_delivery,
        "processed_count": str(len(processed) if isinstance(processed, list) else 0),
        "outbox_count": str(len(outbox_items)),
        "last_state_update": mtime,
        "controller_pubkey": validate_b64(env.get("QUOODLE_CONTROLLER_PUBKEY_B64", "")),
        "agent_privkey": validate_b64(env.get("QUOODLE_AGENT_PRIVKEY_B64", "")),
        "agent_pubkey": validate_b64(env.get("QUOODLE_AGENT_PUBKEY_B64", "")),
        "daemon_pubkey": validate_b64(env.get("QUOODLE_DAEMON_PUBKEY_B64", "")),
        "priv_socket": env.get("QUOODLE_PRIV_SOCKET", "/run/quoodle/privileged.sock"),
        "quarantine": "yes" if priv_state.get("quarantine") else "no",
        "state_path": state_path,
    }


def load_processed_commands(secrets_file: str = DEFAULT_SECRETS) -> List[Dict]:
    env = merged_env(secrets_file)
    state_dir = get_state_dir(env)
    state = read_json(os.path.join(state_dir, "state.json"))
    cmds = state.get("processed_commands", [])
    if not isinstance(cmds, list):
        return []
    return [c for c in cmds if isinstance(c, dict)]


def export_diagnostics(dest_dir: str, secrets_file: str = DEFAULT_SECRETS) -> str:
    env = merged_env(secrets_file)
    state_dir = get_state_dir(env)
    ts = time.strftime("%Y%m%d-%H%M%S", time.gmtime())
    out_dir = Path(dest_dir) / f"quoodle-agent-diag-{ts}"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "env.json").write_text(json.dumps(env, indent=2))

    for name in ("state.json", "outbox.json"):
        src = Path(state_dir) / name
        if src.exists():
            (out_dir / name).write_text(src.read_text())

    logs = journal_tail(["quoodle-agent", "quoodle-privileged"], lines=300)
    (out_dir / "journal.log").write_text(logs)

    return str(out_dir)
