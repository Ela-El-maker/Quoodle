#!/usr/bin/env python3
"""
Run a Linux E2E command suite (Control Plane -> Gateway -> Agent -> Privileged Daemon).
Avoids destructive commands (shutdown/logout/lock_screen).
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import requests
from nacl.signing import SigningKey

ROOT = Path(__file__).resolve().parents[1]


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def write_jsonl(fp, record: dict) -> None:
    fp.write(json.dumps(record, ensure_ascii=False) + "\n")
    fp.flush()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run Linux command suite end-to-end.")
    parser.add_argument("--laravel-base-url", default=os.getenv("LARAVEL_BASE_URL", "http://localhost:8080"))
    parser.add_argument("--fastapi-base-url", default=os.getenv("FASTAPI_BASE_URL", "http://localhost:8000"))
    parser.add_argument("--user-email", default=os.getenv("TEST_USER_EMAIL", "test@example.com"))
    parser.add_argument("--user-password", default=os.getenv("TEST_USER_PASSWORD", "password"))
    parser.add_argument("--user-role", default=os.getenv("TEST_USER_ROLE", "operator"))
    parser.add_argument("--screenshot-user-role", default=os.getenv("SCREENSHOT_USER_ROLE", ""))
    parser.add_argument("--screenshot-2fa", default=os.getenv("SCREENSHOT_TWO_FACTOR_CODE", ""))
    parser.add_argument("--allowed-root", default=os.getenv("QUOODLE_ALLOWED_ROOT", "/home/ela/Work-Force"))
    parser.add_argument("--fixed-hwid", default=os.getenv("FIXED_HWID", ""), help="Stable HWID to reuse device_id across runs.")
    parser.add_argument("--poll-timeout", type=int, default=40)
    parser.add_argument("--poll-interval", type=float, default=2.0)
    return parser.parse_args()


def load_or_create_agent_key(identity_path: Path | None) -> SigningKey:
    if identity_path and identity_path.exists():
        payload = json.loads(identity_path.read_text(encoding="utf-8"))
        priv_b64 = payload.get("priv_b64")
        if priv_b64:
            raw = base64.b64decode(priv_b64)
            return SigningKey(raw[:32])
    key = SigningKey.generate()
    if identity_path:
        identity_path.parent.mkdir(parents=True, exist_ok=True)
        identity_path.write_text(
            json.dumps({"priv_b64": base64.b64encode(key.encode()).decode("ascii")}),
            encoding="utf-8",
        )
    return key


def canonical_json(payload: dict) -> bytes:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def sign_ed25519(payload: dict, priv_b64: str) -> str:
    raw = base64.b64decode(priv_b64)
    seed = raw[:32]
    key = SigningKey(seed)
    sig = key.sign(canonical_json(payload)).signature
    return base64.b64encode(sig).decode("ascii")


def ed25519_pub_from_priv(priv_b64: str) -> str:
    raw = base64.b64decode(priv_b64)
    seed = raw[:32]
    key = SigningKey(seed)
    return base64.b64encode(key.verify_key.encode()).decode("ascii")


def log_request(trace_fp, stage: str, method: str, url: str, request_body: dict | None, response: requests.Response) -> None:
    record = {
        "timestamp": iso_now(),
        "source": "client",
        "event_type": "http",
        "stage": stage,
        "method": method,
        "url": url,
        "status_code": response.status_code,
    }
    if request_body is not None:
        record["request"] = request_body
    try:
        record["response"] = response.json()
    except Exception:
        record["response"] = response.text
    write_jsonl(trace_fp, record)


def start_process(cmd: list[str], env: dict, name: str, trace_fp, log_path: Path) -> subprocess.Popen:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_file = log_path.open("w", encoding="utf-8")
    proc = subprocess.Popen(cmd, env=env, stdout=log_file, stderr=log_file, text=True)

    def watcher() -> None:
        while proc.poll() is None:
            time.sleep(0.5)
        write_jsonl(
            trace_fp,
            {
                "timestamp": iso_now(),
                "source": name,
                "event_type": "process.exit",
                "exit_code": proc.returncode,
                "log_path": str(log_path),
            },
        )

    thread = threading.Thread(target=watcher, daemon=True)
    thread.start()
    write_jsonl(
        trace_fp,
        {
            "timestamp": iso_now(),
            "source": name,
            "event_type": "process.start",
            "cmd": cmd,
            "log_path": str(log_path),
        },
    )
    return proc


def wait_device_online(trace_fp, fastapi_base_url: str, device_id: str, timeout_s: int = 25) -> None:
    online_url = f"{fastapi_base_url}/api/v1/devices/online"
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        resp = requests.get(online_url, timeout=5)
        try:
            devices = resp.json().get("devices", [])
        except Exception:
            devices = []
        online = any(d.get("device_id") == device_id for d in devices)
        write_jsonl(
            trace_fp,
            {
                "timestamp": iso_now(),
                "source": "client",
                "event_type": "gateway.poll",
                "stage": "gateway.device.online",
                "status_code": resp.status_code,
                "device_id": device_id,
                "online": online,
            },
        )
        if online:
            return
        time.sleep(0.5)
    raise RuntimeError("Device did not come online")


def poll_command(trace_fp, base_url: str, headers: dict, command_id: str, timeout_s: int, interval: float) -> dict:
    poll_url = f"{base_url}/api/commands/{command_id}"
    deadline = time.time() + timeout_s
    last = {}
    while time.time() < deadline:
        resp = requests.get(poll_url, headers=headers, timeout=10)
        log_request(trace_fp, "mobile.command.poll", "GET", poll_url, None, resp)
        resp.raise_for_status()
        last = resp.json()
        state = last.get("state")
        if state in ("completed", "failed", "expired"):
            return last
        time.sleep(interval)
    return last


def build_command_suite(allowed_root: str, screenshot_role: str, screenshot_2fa: str) -> list[dict]:
    rel_root = "Quoodle"
    readme_rel = "Quoodle/README.md"
    screenshot_entry = {"method": "screenshot", "params": {}}
    if screenshot_role:
        screenshot_entry["user_role"] = screenshot_role
    if screenshot_2fa:
        screenshot_entry["two_factor_code"] = screenshot_2fa
    return [
        {"method": "sysinfo", "params": {}},
        {"method": "list_processes", "params": {"limit": 15}},
        {"method": "get_users", "params": {}},
        {"method": "get_sessions", "params": {}},
        {"method": "list_services", "params": {}},
        {"method": "network_info", "params": {}},
        {"method": "list_mounts", "params": {}},
        {"method": "get_env_fingerprint", "params": {}},
        screenshot_entry,
        {"method": "list_files", "params": {"path": rel_root, "limit": 25}},
        {"method": "hash_file", "params": {"path": readme_rel, "algo": "sha256"}},
    ]


def main() -> int:
    args = parse_args()
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    log_dir = ROOT / "logs" / "command_suite"
    log_dir.mkdir(parents=True, exist_ok=True)
    trace_path = log_dir / f"linux_command_suite_{ts}.jsonl"
    summary_path = log_dir / f"linux_command_suite_{ts}_summary.json"

    start_iso = iso_now()
    with trace_path.open("w", encoding="utf-8") as trace_fp:
        write_jsonl(
            trace_fp,
            {
                "timestamp": start_iso,
                "source": "runner",
                "event_type": "run.start",
                "laravel_base_url": args.laravel_base_url,
                "fastapi_base_url": args.fastapi_base_url,
                "allowed_root": args.allowed_root,
            },
        )

        # Login
        login_payload = {
            "email": args.user_email,
            "password": args.user_password,
            "device_fingerprint": f"linux-suite-{uuid.uuid4()}",
        }
        login_resp = requests.post(f"{args.laravel_base_url}/api/login", json=login_payload, timeout=10)
        log_request(trace_fp, "mobile.login", "POST", f"{args.laravel_base_url}/api/login", login_payload, login_resp)
        login_resp.raise_for_status()
        login_data = login_resp.json()
        jwt = login_data.get("jwt")
        user_id = login_data.get("user_id")
        user_role = login_data.get("user_role") or args.user_role
        if not jwt:
            raise RuntimeError("Login response missing jwt")
        headers = {"Authorization": f"Bearer {jwt}"}

        # Pair init
        init_payload = {"device_label": "Linux Command Suite Device"}
        init_resp = requests.post(f"{args.laravel_base_url}/api/pair/init", json=init_payload, headers=headers, timeout=10)
        log_request(trace_fp, "mobile.pair.init", "POST", f"{args.laravel_base_url}/api/pair/init", init_payload, init_resp)
        init_resp.raise_for_status()
        init_data = init_resp.json()
        pair_session_id = init_data.get("pair_session_id")

        # Agent keypair (stable when fixed HWID provided)
        identity_path = None
        if args.fixed_hwid:
            identity_path = ROOT / "logs" / "command_suite" / "identities" / f"{args.fixed_hwid}.json"
        agent_sk = load_or_create_agent_key(identity_path)
        agent_priv_b64 = base64.b64encode(agent_sk.encode()).decode("ascii")
        agent_pub_b64 = base64.b64encode(agent_sk.verify_key.encode()).decode("ascii")

        # Pair request (device)
        hwid = args.fixed_hwid or f"LINUX-{uuid.uuid4()}"
        pair_request_payload = {
            "device_name": "Linux Agent",
            "hwid": hwid,
            "pubkey": agent_pub_b64,
        }
        pair_req = requests.post(f"{args.laravel_base_url}/api/pair/request", json=pair_request_payload, timeout=10)
        log_request(trace_fp, "agent.pair.request", "POST", f"{args.laravel_base_url}/api/pair/request", pair_request_payload, pair_req)
        pair_req.raise_for_status()
        pair_data = pair_req.json()
        pair_token = pair_data.get("pair_token")
        device_id = pair_data.get("device_id")
        if not pair_token or not device_id:
            raise RuntimeError("Pair request missing token or device_id")

        # Pair confirm (mobile)
        confirm_payload = {"pair_token": pair_token}
        if pair_session_id:
            confirm_payload["pair_session_id"] = pair_session_id
        confirm_resp = requests.post(f"{args.laravel_base_url}/api/pair/confirm", json=confirm_payload, headers=headers, timeout=10)
        log_request(trace_fp, "mobile.pair.confirm", "POST", f"{args.laravel_base_url}/api/pair/confirm", confirm_payload, confirm_resp)
        confirm_resp.raise_for_status()
        confirm_data = confirm_resp.json()
        agent_jwt = confirm_data.get("agent_jwt")
        if not agent_jwt:
            token_resp = requests.post(f"{args.laravel_base_url}/api/agent/token", json={"pair_token": pair_token}, timeout=10)
            log_request(trace_fp, "agent.token", "POST", f"{args.laravel_base_url}/api/agent/token", {"pair_token": pair_token}, token_resp)
            token_resp.raise_for_status()
            agent_jwt = token_resp.json().get("jwt")
        if not agent_jwt:
            raise RuntimeError("Missing agent_jwt")

        # Sync device key to gateway (Laravel signature)
        compose_text = (ROOT / "docker-compose.yml").read_text(encoding="utf-8")
        for line in compose_text.splitlines():
            if "LARAVEL_SERVICE_PRIVATE_KEY_B64" in line:
                laravel_priv = line.split(":", 1)[1].strip().strip('"')
                break
        else:
            raise RuntimeError("Missing LARAVEL_SERVICE_PRIVATE_KEY_B64 in docker-compose.yml")

        key_payload = {"ed25519_pubkey_b64": agent_pub_b64}
        key_sig = sign_ed25519(key_payload, laravel_priv)
        key_resp = requests.post(
            f"{args.fastapi_base_url}/api/v1/admin/device-keys/{device_id}",
            json=key_payload,
            headers={"X-Laravel-Signature": key_sig},
            timeout=10,
        )
        log_request(trace_fp, "gateway.device_keys.upsert", "POST", f"{args.fastapi_base_url}/api/v1/admin/device-keys/{device_id}", key_payload, key_resp)
        key_resp.raise_for_status()

        # Prepare daemon keys
        daemon_sk = SigningKey.generate()
        daemon_priv_b64 = base64.b64encode(daemon_sk.encode()).decode("ascii")
        daemon_pub_b64 = base64.b64encode(daemon_sk.verify_key.encode()).decode("ascii")

        # Controller pubkey for WSS signature verification
        for line in compose_text.splitlines():
            if "ED25519_PRIVATE_KEY_B64" in line:
                controller_priv = line.split(":", 1)[1].strip().strip('"')
                break
        else:
            raise RuntimeError("Missing ED25519_PRIVATE_KEY_B64 in docker-compose.yml")
        controller_pub_b64 = ed25519_pub_from_priv(controller_priv)

        # Start privileged daemon + agent
        priv_socket = f"/tmp/quoodle_priv_{ts}.sock"
        agent_state = f"/tmp/quoodle-agent-{ts}"
        priv_state = f"/tmp/quoodle-priv-{ts}"

        daemon_env = os.environ.copy()
        daemon_env.update(
            {
                "QUOODLE_PRIV_SOCKET": priv_socket,
                "QUOODLE_DAEMON_PRIVKEY_B64": daemon_priv_b64,
                "QUOODLE_AGENT_PUBKEY_B64": agent_pub_b64,
                "QUOODLE_PRIV_STATE_DIR": priv_state,
                "QUOODLE_ALLOWED_ROOT": args.allowed_root,
                "QUOODLE_AGENT_UID": str(os.getuid()),
                "QUOODLE_AGENT_GID": str(os.getgid()),
            }
        )
        daemon_proc = start_process(
            [sys.executable, "-u", str(ROOT / "quoodle-agent-linux" / "privileged_daemon.py")],
            daemon_env,
            "privileged-daemon",
            trace_fp,
            log_dir / f"linux_daemon_{ts}.log",
        )

        agent_env = os.environ.copy()
        agent_env.update(
            {
                "QUOODLE_WS_URL": f"ws://localhost:8000/agent",
                "QUOODLE_DEVICE_ID": device_id,
                "QUOODLE_AGENT_JWT": agent_jwt,
                "QUOODLE_AGENT_KID": "agent-dev",
                "QUOODLE_AGENT_PRIVKEY_B64": agent_priv_b64,
                "QUOODLE_DAEMON_PUBKEY_B64": daemon_pub_b64,
                "QUOODLE_CONTROLLER_PUBKEY_B64": controller_pub_b64,
                "QUOODLE_AGENT_STATE_DIR": agent_state,
                "QUOODLE_PRIV_SOCKET": priv_socket,
            }
        )
        agent_proc = start_process(
            [str(ROOT / "quoodle-agent-linux" / "build" / "agent" / "quoodle-agent-linux")],
            agent_env,
            "linux-agent",
            trace_fp,
            log_dir / f"linux_agent_{ts}.log",
        )

        wait_device_online(trace_fp, args.fastapi_base_url, device_id)

        suite = build_command_suite(args.allowed_root, args.screenshot_user_role, args.screenshot_2fa)
        results = []

        for entry in suite:
            method = entry["method"]
            params = entry.get("params", {})
            role = entry.get("user_role") or user_role
            two_factor_code = entry.get("two_factor_code")
            command_payload = {
                "client_message_id": str(uuid.uuid4()),
                "device_id": device_id,
                "method": method,
                "params": params,
                "sensitive": False,
                "user_id": user_id,
                "user_role": role,
                "attestation_status": "pass",
            }
            if two_factor_code:
                command_payload["two_factor_code"] = two_factor_code
            cmd_resp = requests.post(f"{args.laravel_base_url}/api/commands", json=command_payload, headers=headers, timeout=10)
            log_request(trace_fp, "mobile.command.enqueue", "POST", f"{args.laravel_base_url}/api/commands", command_payload, cmd_resp)
            if cmd_resp.status_code not in (200, 201):
                results.append({
                    "method": method,
                    "command_id": None,
                    "state": "rejected",
                    "result": None,
                    "error": cmd_resp.json() if cmd_resp.content else {"status_code": cmd_resp.status_code},
                })
                continue
            cmd_data = cmd_resp.json()
            command_id = cmd_data.get("command_id")
            if not command_id:
                raise RuntimeError(f"Command response missing command_id for {method}")

            final = poll_command(trace_fp, args.laravel_base_url, headers, command_id, args.poll_timeout, args.poll_interval)
            results.append({
                "method": method,
                "command_id": command_id,
                "state": final.get("state"),
                "result": final.get("result"),
                "error": final.get("error"),
            })

        # Stop processes
        agent_proc.terminate()
        daemon_proc.terminate()
        agent_proc.wait(timeout=5)
        daemon_proc.wait(timeout=5)

        summary = {
            "device_id": device_id,
            "commands": results,
            "trace_log": str(trace_path),
            "agent_log": str(log_dir / f"linux_agent_{ts}.log"),
            "daemon_log": str(log_dir / f"linux_daemon_{ts}.log"),
        }
        write_jsonl(trace_fp, {"timestamp": iso_now(), "source": "runner", "event_type": "run.complete", "summary": summary})

    with summary_path.open("w", encoding="utf-8") as fp:
        json.dump(summary, fp, ensure_ascii=False, indent=2)

    print(f"Trace log: {trace_path}")
    print(f"Summary: {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
