#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PY="$ROOT/quoodle-agent-linux/venv/bin/python"
PYTHON="${VENV_PY}"

if [[ ! -x "$PYTHON" ]]; then
  PYTHON="python3"
fi

if ! "$PYTHON" - <<'PY' >/dev/null 2>&1; then
import requests
from nacl.signing import SigningKey
PY
  echo "Python deps missing. Install venv deps: $ROOT/quoodle-agent-linux/venv/bin/pip install -r $ROOT/quoodle-agent-linux/requirements.txt"
  exit 1
fi

SETUP_OUTPUT="$("$PYTHON" "$ROOT/scripts/setup_linux_agent_secrets.py")"
echo "$SETUP_OUTPUT"

SECRETS_PATH="$(echo "$SETUP_OUTPUT" | python3 -c "import sys, json; print(json.load(sys.stdin)['output'])")"

sudo install -m 600 "$SECRETS_PATH" /etc/quoodle/secrets.env
sudo "$ROOT/scripts/install_linux_agent_systemd.sh"
