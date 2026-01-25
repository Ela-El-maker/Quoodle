#!/usr/bin/env python3
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
    parser = argparse.ArgumentParser(description="Run Linux agent end-to-end flow with full trace logging.")
    parser.add_argument("--laravel-base-url", default=os.getenv("LARAVEL_BASE_URL", "http://localhost:8080"))
    parser.add_argument("--fastapi-base-url", default=os.getenv("FASTAPI_BASE_URL", "http://localhost:8000"))
    parser.add_argument("--user-email", default=os.getenv("TEST_USER_EMAIL", "test@example.com"))
    parser.add_argument("--user-password", default=os.getenv("TEST_USER_PASSWORD", "password"))
    parser.add_argument("--method", default="lock_screen")
    parser.add_argument("--params", default=None)
    parser.add_argument("--spawn-sleep-seconds", type=int, default=120)
    parser.add_argument("--attestation-status", default=None)
    return parser.parse_args()


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


def docker_logs_since(trace_fp, since_iso: str, container: str) -> None:
    cmd = ["docker", "logs", "--since", since_iso, "--timestamps", container]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        write_jsonl(
            trace_fp,
            {
                "timestamp": iso_now(),
                "source": f"docker:{container}",
                "event_type": "log.error",
                "message": result.stderr.strip(),
            },
        )
        return
    for line in result.stdout.splitlines():
        ts = None
        msg = line
        if " " in line and line[:4].isdigit():
            possible_ts, rest = line.split(" ", 1)
            if possible_ts.endswith("Z"):
                ts = possible_ts
                msg = rest
        write_jsonl(
            trace_fp,
            {
                "timestamp": ts or iso_now(),
                "source": f"docker:{container}",
                "event_type": "log",
                "message": msg,
            },
        )


def fetch_outbox_events(command_id: str) -> list[dict]:
    script = """
import json
import sqlite3
import sys

cmd = sys.argv[1]
conn = sqlite3.connect('/app/data/webhook_outbox.db')
rows = conn.execute(
    'SELECT event_type,status,payload_json,attempts,last_error,created_at,updated_at FROM webhook_outbox ORDER BY created_at ASC'
).fetchall()
events = []
for event_type, status, payload_json, attempts, last_error, created_at, updated_at in rows:
    try:
        payload = json.loads(payload_json)
    except Exception:
        continue
    if payload.get('command_id') != cmd:
        continue
    events.append({
        'event_type': event_type,
        'status': status,
        'attempts': attempts,
        'last_error': last_error,
        'created_at': created_at,
        'updated_at': updated_at,
        'payload': payload,
    })
print(json.dumps(events))
"""
    result = subprocess.run(
        ["docker", "exec", "-i", "quoodle-gateway", "python", "-", command_id],
        input=script,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        return []
    try:
        return json.loads(result.stdout.strip() or "[]")
    except Exception:
        return []


def main() -> int:
    args = parse_args()
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    log_dir = ROOT / "logs" / "full_trace"
    log_dir.mkdir(parents=True, exist_ok=True)
    trace_path = log_dir / f"linux_full_flow_{ts}.jsonl"
    summary_path = log_dir / f"linux_full_flow_{ts}_summary.json"

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
            },
        )

        # Login
        login_payload = {
            "email": args.user_email,
            "password": args.user_password,
            "device_fingerprint": f"linux-flow-{uuid.uuid4()}",
        }
        login_resp = requests.post(f"{args.laravel_base_url}/api/login", json=login_payload, timeout=10)
        log_request(trace_fp, "mobile.login", "POST", f"{args.laravel_base_url}/api/login", login_payload, login_resp)
        login_resp.raise_for_status()
        login_data = login_resp.json()
        jwt = login_data.get("jwt")
        user_id = login_data.get("user_id")
        user_role = login_data.get("user_role")
        if not jwt:
            raise RuntimeError("Login response missing jwt")

        headers = {"Authorization": f"Bearer {jwt}"}

        # Pair init
        init_payload = {"device_label": "Linux Flow Device"}
        init_resp = requests.post(f"{args.laravel_base_url}/api/pair/init", json=init_payload, headers=headers, timeout=10)
        log_request(trace_fp, "mobile.pair.init", "POST", f"{args.laravel_base_url}/api/pair/init", init_payload, init_resp)
        init_resp.raise_for_status()
        init_data = init_resp.json()
        pair_session_id = init_data.get("pair_session_id")

        # Agent keypair
        agent_sk = SigningKey.generate()
        agent_priv_b64 = base64.b64encode(agent_sk.encode()).decode("ascii")
        agent_pub_b64 = base64.b64encode(agent_sk.verify_key.encode()).decode("ascii")

        # Pair request (device)
        hwid = f"LINUX-{uuid.uuid4()}"
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
            # fallback to agent/token
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
                "QUOODLE_PRIV_ALLOWED_UID": str(os.getuid()),
                "QUOODLE_PRIV_ALLOWED_GID": str(os.getgid()),
            }
        )
        daemon_proc = start_process(
            [str(ROOT / "quoodle-agent-linux" / "build" / "privileged" / "quoodle-privileged-daemon")],
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

        # Wait for device online
        online_url = f"{args.fastapi_base_url}/api/v1/devices/online"
        deadline = time.time() + 20
        online = False
        while time.time() < deadline:
            resp = requests.get(online_url, timeout=5)
            try:
                devices = resp.json().get("devices", [])
            except Exception:
                devices = []
            write_jsonl(
                trace_fp,
                {
                    "timestamp": iso_now(),
                    "source": "client",
                    "event_type": "gateway.poll",
                    "stage": "gateway.device.online",
                    "status_code": resp.status_code,
                    "device_id": device_id,
                    "online": any(d.get("device_id") == device_id for d in devices),
                },
            )
            if any(d.get("device_id") == device_id for d in devices):
                online = True
                break
            time.sleep(0.5)
        if not online:
            raise RuntimeError("Device did not come online")

        command_params = {}
        spawned_proc = None
        if args.params:
            try:
                command_params = json.loads(args.params)
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"Invalid --params JSON: {exc}") from exc
        elif args.method == "kill_process":
            spawned_proc = subprocess.Popen(["sleep", str(args.spawn_sleep_seconds)])
            command_params = {"pid": spawned_proc.pid, "signal": 15}
            write_jsonl(
                trace_fp,
                {
                    "timestamp": iso_now(),
                    "source": "runner",
                    "event_type": "local.process.start",
                    "pid": spawned_proc.pid,
                    "command": "sleep",
                    "seconds": args.spawn_sleep_seconds,
                },
            )

        # Send command
        command_payload = {
            "client_message_id": str(uuid.uuid4()),
            "device_id": device_id,
            "method": args.method,
            "params": command_params,
            "sensitive": False,
            "user_id": user_id,
        }
        if args.attestation_status:
            command_payload["attestation_status"] = args.attestation_status
        elif args.method in ("kill_process", "list_processes"):
            command_payload["attestation_status"] = "pass"
        if user_role in ("user", "operator", "analyst", "admin"):
            command_payload["user_role"] = user_role
        cmd_resp = requests.post(f"{args.laravel_base_url}/api/commands", json=command_payload, headers=headers, timeout=10)
        log_request(trace_fp, "mobile.command.enqueue", "POST", f"{args.laravel_base_url}/api/commands", command_payload, cmd_resp)
        cmd_resp.raise_for_status()
        cmd_data = cmd_resp.json()
        command_id = cmd_data.get("command_id")
        if not command_id:
            raise RuntimeError("Command response missing command_id")

        # Poll command state
        poll_url = f"{args.laravel_base_url}/api/commands/{command_id}"
        final_state = None
        deadline = time.time() + 30
        while time.time() < deadline:
            poll_resp = requests.get(poll_url, headers=headers, timeout=10)
            log_request(trace_fp, "mobile.command.poll", "GET", poll_url, None, poll_resp)
            poll_resp.raise_for_status()
            data = poll_resp.json()
            state = data.get("state")
            if state in ("completed", "failed", "expired"):
                final_state = state
                break
            time.sleep(2)

        # Capture gateway outbox for the command
        outbox_events = fetch_outbox_events(command_id)
        for event in outbox_events:
            write_jsonl(
                trace_fp,
                {
                    "timestamp": event.get("created_at") or iso_now(),
                    "source": "gateway.outbox",
                    "event_type": event.get("event_type"),
                    "status": event.get("status"),
                    "attempts": event.get("attempts"),
                    "last_error": event.get("last_error"),
                    "payload": event.get("payload"),
                },
            )

        # Capture docker logs
        docker_logs_since(trace_fp, start_iso, "quoodle-control-plane")
        docker_logs_since(trace_fp, start_iso, "quoodle-gateway")

        if spawned_proc:
            poll_rc = spawned_proc.poll()
            if poll_rc is None:
                try:
                    spawned_proc.terminate()
                    spawned_proc.wait(timeout=5)
                    proc_status = "terminated"
                except Exception:
                    spawned_proc.kill()
                    proc_status = "killed"
            else:
                proc_status = "exited"
            write_jsonl(
                trace_fp,
                {
                    "timestamp": iso_now(),
                    "source": "runner",
                    "event_type": "local.process.end",
                    "pid": spawned_proc.pid,
                    "status": proc_status,
                },
            )

        # Stop processes
        agent_proc.terminate()
        daemon_proc.terminate()
        agent_proc.wait(timeout=5)
        daemon_proc.wait(timeout=5)

        summary = {
            "device_id": device_id,
            "command_id": command_id,
            "method": args.method,
            "params": command_params,
            "final_state": final_state,
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
