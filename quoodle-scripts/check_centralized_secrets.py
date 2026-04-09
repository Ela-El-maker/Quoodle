#!/usr/bin/env python3
"""
Validate required centralized secrets in the root .env file.

Usage:
  python quoodle-scripts/check_centralized_secrets.py
  python quoodle-scripts/check_centralized_secrets.py --env-file .env
"""

from __future__ import annotations

import argparse
import pathlib
import sys


REQUIRED_KEYS = [
    "MYSQL_ROOT_PASSWORD",
    "MYSQL_PASSWORD",
    "APP_KEY",
    "POLICY_HASH",
    "LARAVEL_SERVICE_PRIVATE_KEY_B64",
    "LARAVEL_SERVICE_PUBKEY_B64",
    "FASTAPI_SERVICE_PRIVATE_KEY_B64",
    "FASTAPI_SERVICE_PUBLIC_KEY_B64",
    "ED25519_PRIVATE_KEY_B64",
    "GOOGLE_CLIENT_ID",
    "GOOGLE_CLIENT_SECRET",
    "MAIL_HOST",
    "MAIL_PORT",
    "MAIL_USERNAME",
    "MAIL_PASSWORD",
    "MAIL_FROM_ADDRESS",
]


def parse_env_file(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        values[key] = value
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=".env", help="Path to env file")
    args = parser.parse_args()

    env_path = pathlib.Path(args.env_file)
    if not env_path.exists():
        print(f"[error] env file not found: {env_path}")
        return 2

    values = parse_env_file(env_path)
    missing = [k for k in REQUIRED_KEYS if not values.get(k) or values.get(k) in {"replace_me", "change_me"}]

    if missing:
        print("[error] missing required centralized secrets:")
        for key in missing:
            print(f" - {key}")
        return 1

    print("[ok] centralized secret checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
