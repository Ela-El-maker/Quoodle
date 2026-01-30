#!/usr/bin/env python3
import argparse
import base64
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


DEFAULT_STATE_DIRS = [
    "/var/lib/quoodle-agent/state",
    "/var/lib/quoodle/agent",
]


def read_env_file(path: str) -> dict:
    env = {}
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


def get_state_dir() -> str:
    env_dir = os.getenv("QUOODLE_AGENT_STATE_DIR")
    if env_dir:
        return env_dir
    for candidate in DEFAULT_STATE_DIRS:
        if os.path.isdir(candidate):
            return candidate
    return DEFAULT_STATE_DIRS[0]


def read_json(path: str) -> dict:
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


def print_status(args: argparse.Namespace) -> int:
    env = read_env_file(args.secrets_file) if args.secrets_file else {}
    state_dir = get_state_dir()
    state = read_json(os.path.join(state_dir, "state.json"))
    outbox = read_json(os.path.join(state_dir, "outbox.json"))

    device_id = os.getenv("QUOODLE_DEVICE_ID") or env.get("QUOODLE_DEVICE_ID", "-")
    ws_url = os.getenv("QUOODLE_WS_URL") or env.get("QUOODLE_WS_URL", "-")
    jwt = os.getenv("QUOODLE_AGENT_JWT") or env.get("QUOODLE_AGENT_JWT", "")

    print("Quoodle Linux Agent")
    print(f"Device ID: {device_id}")
    print(f"WSS URL: {ws_url}")
    print(f"Agent JWT: {mask(jwt)}")
    print(f"State dir: {state_dir}")
    print(f"Systemd agent: {check_systemctl('quoodle-agent')}")
    print(f"Systemd privileged: {check_systemctl('quoodle-privileged')}")

    policy_hash = state.get("policy_hash", "-")
    sequence = state.get("sequence", "-")
    last_delivery = state.get("last_delivery_id", "-")
    processed = state.get("processed_commands", [])
    queued_outbox = outbox.get("items", []) if isinstance(outbox, dict) else []

    print(f"Policy hash: {policy_hash}")
    print(f"Sequence: {sequence}")
    print(f"Last delivery: {last_delivery}")
    print(f"Processed commands: {len(processed)}")
    print(f"Outbox items: {len(queued_outbox)}")
    return 0


def validate_b64(label: str, value: str, min_len: int = 16) -> str:
    if not value:
        return f"{label}: MISSING"
    try:
        raw = base64.b64decode(value.encode("utf-8"))
        if len(raw) < min_len:
            return f"{label}: INVALID (too short)"
        return f"{label}: OK"
    except Exception:
        return f"{label}: INVALID (base64 decode failed)"


def print_doctor(args: argparse.Namespace) -> int:
    env = read_env_file(args.secrets_file) if args.secrets_file else {}
    env = {**env, **{k: v for k, v in os.environ.items() if v}}

    checks = []
    checks.append(("QUOODLE_WS_URL", "set" if env.get("QUOODLE_WS_URL") else "missing"))
    checks.append(("QUOODLE_DEVICE_ID", "set" if env.get("QUOODLE_DEVICE_ID") else "missing"))
    checks.append(("QUOODLE_AGENT_JWT", "set" if env.get("QUOODLE_AGENT_JWT") else "missing"))
    checks.append(("QUOODLE_AGENT_PRIVKEY_B64", validate_b64("AGENT_PRIVKEY", env.get("QUOODLE_AGENT_PRIVKEY_B64", ""))))
    checks.append(("QUOODLE_AGENT_PUBKEY_B64", validate_b64("AGENT_PUBKEY", env.get("QUOODLE_AGENT_PUBKEY_B64", ""))))
    checks.append(("QUOODLE_CONTROLLER_PUBKEY_B64", validate_b64("CONTROLLER_PUBKEY", env.get("QUOODLE_CONTROLLER_PUBKEY_B64", ""))))
    checks.append(("QUOODLE_DAEMON_PUBKEY_B64", validate_b64("DAEMON_PUBKEY", env.get("QUOODLE_DAEMON_PUBKEY_B64", ""))))

    priv_socket = env.get("QUOODLE_PRIV_SOCKET", "/run/quoodle/privileged.sock")
    socket_ok = os.path.exists(priv_socket)

    state_dir = get_state_dir()
    state_ok = os.access(state_dir, os.W_OK) if os.path.isdir(state_dir) else False

    print("Quoodle Linux Agent Doctor")
    for name, status in checks:
        print(f"{name}: {status}")
    print(f"Privileged socket: {'present' if socket_ok else 'missing'} ({priv_socket})")
    print(f"State dir writable: {'yes' if state_ok else 'no'} ({state_dir})")
    print(f"Systemd agent: {check_systemctl('quoodle-agent')}")
    print(f"Systemd privileged: {check_systemctl('quoodle-privileged')}")
    return 0


def print_logs(args: argparse.Namespace) -> int:
    units = []
    if args.service in ("agent", "both"):
        units.append("quoodle-agent")
    if args.service in ("privileged", "both"):
        units.append("quoodle-privileged")

    cmd = ["journalctl"]
    for unit in units:
        cmd.extend(["-u", unit])
    cmd.extend(["-n", str(args.tail)])
    if args.follow:
        cmd.append("-f")
    return subprocess.call(cmd)


def http_json(url: str, payload: dict, headers: dict) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = resp.read().decode("utf-8")
        return json.loads(body)


def load_machine_id() -> str:
    for path in ("/etc/machine-id", "/var/lib/dbus/machine-id"):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read().strip()
        except FileNotFoundError:
            continue
    return ""


def handle_pair(args: argparse.Namespace) -> int:
    env = read_env_file(args.secrets_file) if args.secrets_file else {}
    env = {**env, **{k: v for k, v in os.environ.items() if v}}

    api_base = args.api_base or env.get("QUOODLE_API_BASE") or env.get("QUOODLE_CONTROL_PLANE")
    if not api_base:
        print("Missing --api-base or QUOODLE_API_BASE", file=sys.stderr)
        return 1
    api_base = api_base.rstrip("/")

    device_name = args.device_name or socket.gethostname()
    hwid = args.hwid or load_machine_id() or "linux-unknown"
    pubkey = args.pubkey or env.get("QUOODLE_AGENT_PUBKEY_B64")
    if not pubkey:
        print("Missing agent public key (set QUOODLE_AGENT_PUBKEY_B64 or --pubkey)", file=sys.stderr)
        return 1

    user_jwt = args.user_jwt or env.get("QUOODLE_USER_JWT")
    if not user_jwt:
        print("Missing user JWT (set QUOODLE_USER_JWT or --user-jwt)", file=sys.stderr)
        return 1

    pair_request = http_json(
        f"{api_base}/api/pair/request",
        {"device_name": device_name, "hwid": hwid, "pubkey": pubkey},
        {"Content-Type": "application/json"},
    )
    pair_token = pair_request.get("pair_token")
    if not pair_token:
        print("Failed to get pair token", file=sys.stderr)
        print(json.dumps(pair_request, indent=2))
        return 1

    pair_confirm = http_json(
        f"{api_base}/api/pair/confirm",
        {"pair_token": pair_token},
        {"Content-Type": "application/json", "Authorization": f"Bearer {user_jwt}"},
    )
    agent_jwt = pair_confirm.get("agent_jwt")
    if not agent_jwt:
        print("Pair confirm failed", file=sys.stderr)
        print(json.dumps(pair_confirm, indent=2))
        return 1

    print("Pairing complete")
    print(f"Device ID: {pair_confirm.get('device_id')}")
    print(f"Lifecycle: {pair_confirm.get('lifecycle_state')}")
    print(f"Agent JWT: {agent_jwt}")

    if args.update_secrets and args.secrets_file:
        update_secrets(args.secrets_file, "QUOODLE_AGENT_JWT", agent_jwt)
        print(f"Updated secrets file: {args.secrets_file}")
    return 0


def update_secrets(path: str, key: str, value: str) -> None:
    lines = []
    found = False
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith(f"{key}="):
                    lines.append(f"{key}={value}\n")
                    found = True
                else:
                    lines.append(line)
    except FileNotFoundError:
        pass

    if not found:
        lines.append(f"{key}={value}\n")
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.writelines(lines)
    os.replace(tmp, path)


def handle_attest(_: argparse.Namespace) -> int:
    machine_id = load_machine_id()
    if not machine_id:
        print("Attestation unavailable (no machine-id).", file=sys.stderr)
        return 1
    digest = base64.b64encode(
        __import__("hashlib").sha256(machine_id.encode("utf-8")).digest()
    ).decode("utf-8")
    print("Attestation snapshot")
    print(f"machine_id: {machine_id}")
    print(f"attestation_hash: {digest}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="quoodle-agent", description="Quoodle Linux Agent CLI")
    parser.add_argument("--secrets-file", default="/etc/quoodle/secrets.env")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="Show agent status")
    sub.add_parser("doctor", help="Run health checks")

    logs = sub.add_parser("logs", help="Show agent logs")
    logs.add_argument("--service", choices=["agent", "privileged", "both"], default="both")
    logs.add_argument("--tail", type=int, default=200)
    logs.add_argument("--follow", action="store_true")

    pair = sub.add_parser("pair", help="Pair device without QR")
    pair.add_argument("--api-base", help="Control plane base URL (e.g. http://localhost:8080)")
    pair.add_argument("--device-name")
    pair.add_argument("--hwid")
    pair.add_argument("--pubkey")
    pair.add_argument("--user-jwt")
    pair.add_argument("--update-secrets", action="store_true")

    sub.add_parser("attest", help="Generate a local attestation hash")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "status":
        return print_status(args)
    if args.command == "doctor":
        return print_doctor(args)
    if args.command == "logs":
        return print_logs(args)
    if args.command == "pair":
        return handle_pair(args)
    if args.command == "attest":
        return handle_attest(args)
    return 1


if __name__ == "__main__":
    sys.exit(main())
