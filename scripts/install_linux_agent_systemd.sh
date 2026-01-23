#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="/opt/quoodle-agent/bin"
SYSTEMD_DIR="/etc/systemd/system"
SECRETS="/etc/quoodle/secrets.env"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo: sudo $0"
  exit 1
fi

if [[ ! -f "$SECRETS" ]]; then
  echo "Missing $SECRETS. Create it first (see scripts/setup_linux_agent_secrets.py)."
  exit 1
fi

if [[ ! -x "$ROOT/quoodle-agent-linux/build/agent/quoodle-agent-linux" ]]; then
  echo "Missing agent binary. Build first: cmake --build $ROOT/quoodle-agent-linux/build"
  exit 1
fi

if [[ ! -x "$ROOT/quoodle-agent-linux/build/privileged/quoodle-privileged-daemon" ]]; then
  echo "Missing privileged daemon binary. Build first: cmake --build $ROOT/quoodle-agent-linux/build"
  exit 1
fi

if ! getent group quoodle-agent >/dev/null; then
  groupadd --system quoodle-agent
fi

if ! id -u quoodle-agent >/dev/null 2>&1; then
  useradd --system --home /var/lib/quoodle-agent --shell /usr/sbin/nologin --gid quoodle-agent quoodle-agent
fi

install -d -m 0755 "$BIN_DIR"
install -m 0755 "$ROOT/quoodle-agent-linux/build/agent/quoodle-agent-linux" "$BIN_DIR/quoodle-agent-linux"
install -m 0755 "$ROOT/quoodle-agent-linux/build/privileged/quoodle-privileged-daemon" "$BIN_DIR/quoodle-privileged-daemon"

install -d -m 0750 -o quoodle-agent -g quoodle-agent /var/lib/quoodle-agent/state

install -m 0644 "$ROOT/quoodle-agent-linux/systemd/quoodle-agent.service" "$SYSTEMD_DIR/quoodle-agent.service"
install -m 0644 "$ROOT/quoodle-agent-linux/systemd/quoodle-privileged.service" "$SYSTEMD_DIR/quoodle-privileged.service"

systemctl daemon-reload
systemctl enable --now quoodle-privileged.service quoodle-agent.service

echo "Installed and started systemd services."
