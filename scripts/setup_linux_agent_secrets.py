#!/usr/bin/env python3
import argparse
import base64
import json
import os
import sys
import uuid

import requests
from nacl.signing import SigningKey


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def controller_pubkey_from_compose(path: str) -> str:
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            if "ED25519_PRIVATE_KEY_B64" in line:
                value = line.split(":", 1)[1].strip().strip('"')
                raw = base64.b64decode(value)
                seed = raw[:32]
                key = SigningKey(seed)
                return b64(key.verify_key.encode())
    raise RuntimeError("ED25519_PRIVATE_KEY_B64 not found in docker-compose.yml")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate Linux agent secrets and pair device.")
    parser.add_argument("--laravel-base-url", default=os.getenv("LARAVEL_BASE_URL", "http://localhost:8080"))
    parser.add_argument("--email", default=os.getenv("TEST_USER_EMAIL", "test@example.com"))
    parser.add_argument("--password", default=os.getenv("TEST_USER_PASSWORD", "password"))
    parser.add_argument("--device-name", default="KDE-Linux")
    parser.add_argument(
        "--output",
        default=os.path.join(ROOT, "quoodle-agent-linux", "systemd", "secrets.env.generated"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    agent_key = SigningKey.generate()
    daemon_key = SigningKey.generate()

    agent_priv_b64 = b64(agent_key.encode())
    agent_pub_b64 = b64(agent_key.verify_key.encode())
    daemon_priv_b64 = b64(daemon_key.encode())
    daemon_pub_b64 = b64(daemon_key.verify_key.encode())

    login_payload = {
        "email": args.email,
        "password": args.password,
        "device_fingerprint": f"linux-{uuid.uuid4()}",
    }
    login_resp = requests.post(f"{args.laravel_base_url}/api/login", json=login_payload, timeout=10)
    if login_resp.status_code != 200:
        raise RuntimeError(f"Login failed: {login_resp.status_code} {login_resp.text}")
    user_jwt = login_resp.json().get("jwt")
    if not user_jwt:
        raise RuntimeError("Login response missing jwt")

    hwid = f"linux-{uuid.uuid4()}"
    pair_payload = {"device_name": args.device_name, "hwid": hwid, "pubkey": agent_pub_b64}
    pair_resp = requests.post(f"{args.laravel_base_url}/api/pair/request", json=pair_payload, timeout=10)
    if pair_resp.status_code != 200:
        raise RuntimeError(f"Pair request failed: {pair_resp.status_code} {pair_resp.text}")
    pair_data = pair_resp.json()
    pair_token = pair_data.get("pair_token")
    device_id = pair_data.get("device_id")
    if not pair_token or not device_id:
        raise RuntimeError(f"Pair response missing fields: {pair_data}")

    confirm_payload = {"pair_token": pair_token}
    confirm_resp = requests.post(
        f"{args.laravel_base_url}/api/pair/confirm",
        json=confirm_payload,
        headers={"Authorization": f"Bearer {user_jwt}"},
        timeout=10,
    )
    if confirm_resp.status_code != 200:
        raise RuntimeError(f"Pair confirm failed: {confirm_resp.status_code} {confirm_resp.text}")
    confirm_data = confirm_resp.json()
    agent_jwt = confirm_data.get("agent_jwt")
    if not agent_jwt:
        raise RuntimeError(f"Pair confirm missing agent_jwt: {confirm_data}")

    controller_pub_b64 = controller_pubkey_from_compose(os.path.join(ROOT, "docker-compose.yml"))

    secrets = [
        f"QUOODLE_DEVICE_ID={device_id}",
        f"QUOODLE_AGENT_JWT={agent_jwt}",
        f"QUOODLE_AGENT_PRIVKEY_B64={agent_priv_b64}",
        "QUOODLE_AGENT_KID=agent-dev",
        f"QUOODLE_CONTROLLER_PUBKEY_B64={controller_pub_b64}",
        "",
        f"QUOODLE_DAEMON_PRIVKEY_B64={daemon_priv_b64}",
        f"QUOODLE_DAEMON_PUBKEY_B64={daemon_pub_b64}",
        f"QUOODLE_AGENT_PUBKEY_B64={agent_pub_b64}",
        "",
    ]

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as handle:
        handle.write("\n".join(secrets))

    summary = {
        "output": args.output,
        "device_id": device_id,
        "pair_token": pair_token,
        "agent_jwt_expires_at": confirm_data.get("agent_jwt_expires_at"),
    }
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
