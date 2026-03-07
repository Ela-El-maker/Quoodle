#!/usr/bin/env python3
import argparse
import base64
import json
import os
import socket
import sys
from pathlib import Path

import requests
from nacl.signing import SigningKey


ROOT = Path(__file__).resolve().parent.parent


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def read_machine_id() -> str:
    for candidate in (Path("/etc/machine-id"), Path("/var/lib/dbus/machine-id")):
        try:
            value = candidate.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if value:
            return value
    raise RuntimeError("Unable to read machine-id from /etc/machine-id or /var/lib/dbus/machine-id")


def load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def ensure_keypair(existing: dict[str, str], private_key_name: str, public_key_name: str) -> tuple[str, str]:
    private_key = existing.get(private_key_name)
    public_key = existing.get(public_key_name)
    if private_key and public_key:
        return private_key, public_key

    signing_key = SigningKey.generate()
    return b64(signing_key.encode()), b64(signing_key.verify_key.encode())


def controller_pubkey_from_compose(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        if "ED25519_PRIVATE_KEY_B64" not in line:
            continue
        value = line.split(":", 1)[1].strip().strip('"')
        raw = base64.b64decode(value)
        seed = raw[:32]
        key = SigningKey(seed)
        return b64(key.verify_key.encode())
    raise RuntimeError("ED25519_PRIVATE_KEY_B64 not found in docker-compose.yml")


def post_json(url: str, payload: dict, *, headers: dict | None = None) -> requests.Response:
    return requests.post(url, json=payload, headers=headers, timeout=10)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Pair the real Linux host and write agent secrets.")
    parser.add_argument("--laravel-base-url", default=os.getenv("LARAVEL_BASE_URL", "http://localhost:8088"))
    parser.add_argument("--email", default=os.getenv("DEV_ADMIN_EMAIL", os.getenv("TEST_USER_EMAIL", "admin@quoodle.com")))
    parser.add_argument("--password", default=os.getenv("DEV_ADMIN_PASSWORD", os.getenv("TEST_USER_PASSWORD", "password")))
    parser.add_argument("--device-name", default=socket.gethostname())
    parser.add_argument("--hwid", default=os.getenv("QUOODLE_HWID", read_machine_id()))
    parser.add_argument(
        "--output",
        default=os.path.join(os.path.expanduser("~"), ".config", "quoodle", "secrets.env"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_path = Path(args.output).expanduser()
    existing = load_env_file(output_path)

    agent_priv_b64, agent_pub_b64 = ensure_keypair(
        existing,
        "QUOODLE_AGENT_PRIVKEY_B64",
        "QUOODLE_AGENT_PUBKEY_B64",
    )
    daemon_priv_b64, daemon_pub_b64 = ensure_keypair(
        existing,
        "QUOODLE_DAEMON_PRIVKEY_B64",
        "QUOODLE_DAEMON_PUBKEY_B64",
    )

    login_payload = {
        "email": args.email,
        "password": args.password,
        "device_fingerprint": f"linux-{args.hwid}",
    }
    login_resp = post_json(f"{args.laravel_base_url}/api/login", login_payload)
    if login_resp.status_code != 200:
        raise RuntimeError(f"Login failed: {login_resp.status_code} {login_resp.text}")

    login_data = login_resp.json()
    user_jwt = login_data.get("jwt")
    if not user_jwt:
        raise RuntimeError("Login response missing jwt")

    auth_headers = {"Authorization": f"Bearer {user_jwt}"}

    init_resp = post_json(
        f"{args.laravel_base_url}/api/pair/init",
        {"device_label": args.device_name},
        headers=auth_headers,
    )
    if init_resp.status_code != 200:
        raise RuntimeError(f"Pair init failed: {init_resp.status_code} {init_resp.text}")

    pair_session_id = init_resp.json().get("pair_session_id")
    if not pair_session_id:
        raise RuntimeError("Pair init response missing pair_session_id")

    pair_resp = post_json(
        f"{args.laravel_base_url}/api/pair/request",
        {"device_name": args.device_name, "hwid": args.hwid, "pubkey": agent_pub_b64},
    )
    if pair_resp.status_code != 200:
        raise RuntimeError(f"Pair request failed: {pair_resp.status_code} {pair_resp.text}")

    pair_data = pair_resp.json()
    pair_token = pair_data.get("pair_token")
    device_id = pair_data.get("device_id")
    if not pair_token or not device_id:
        raise RuntimeError(f"Pair response missing fields: {pair_data}")

    confirm_resp = post_json(
        f"{args.laravel_base_url}/api/pair/confirm",
        {"pair_token": pair_token, "pair_session_id": pair_session_id},
        headers=auth_headers,
    )
    if confirm_resp.status_code != 200:
        raise RuntimeError(f"Pair confirm failed: {confirm_resp.status_code} {confirm_resp.text}")

    confirm_data = confirm_resp.json()
    agent_jwt = confirm_data.get("agent_jwt")
    if not agent_jwt:
        raise RuntimeError(f"Pair confirm missing agent_jwt: {confirm_data}")

    controller_pub_b64 = controller_pubkey_from_compose(ROOT / "docker-compose.yml")

    secrets = [
        "# Real host-paired Quoodle agent secrets.",
        f"QUOODLE_DEVICE_ID={device_id}",
        f"QUOODLE_HWID={args.hwid}",
        f"QUOODLE_AGENT_JWT={agent_jwt}",
        f"QUOODLE_AGENT_PRIVKEY_B64={agent_priv_b64}",
        "QUOODLE_AGENT_KID=agent-dev",
        f"QUOODLE_CONTROLLER_PUBKEY_B64={controller_pub_b64}",
        "",
        "# Privileged boundary trust.",
        f"QUOODLE_DAEMON_PRIVKEY_B64={daemon_priv_b64}",
        f"QUOODLE_DAEMON_PUBKEY_B64={daemon_pub_b64}",
        f"QUOODLE_AGENT_PUBKEY_B64={agent_pub_b64}",
        "",
    ]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(secrets), encoding="utf-8")

    summary = {
        "output": str(output_path),
        "device_id": device_id,
        "hwid": args.hwid,
        "device_name": args.device_name,
        "agent_jwt_expires_at": confirm_data.get("agent_jwt_expires_at"),
        "next_steps": [
            f"sudo cp {output_path} /etc/quoodle/secrets.env",
            "sudo systemctl daemon-reload",
            "sudo systemctl restart quoodle-privileged quoodle-agent",
        ],
    }
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
