#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SYSTEMD_DIR="${HOME}/.config/systemd/user"

EXEC_START="${ROOT_DIR}/ui/quoodle-agent-ui"

mkdir -p "${SYSTEMD_DIR}"

sed "s|{{EXEC_START}}|${EXEC_START}|g" "${ROOT_DIR}/systemd-user/quoodle-agent-ui.service.template" \
  > "${SYSTEMD_DIR}/quoodle-agent-ui.service"

sed "s|{{EXEC_START}}|${EXEC_START}|g" "${ROOT_DIR}/systemd-user/quoodle-agent-tray.service.template" \
  > "${SYSTEMD_DIR}/quoodle-agent-tray.service"

systemctl --user daemon-reload
echo "Installed user services:"
echo "  quoodle-agent-ui.service"
echo "  quoodle-agent-tray.service"
echo ""
echo "Enable one of them:"
echo "  systemctl --user enable --now quoodle-agent-ui.service"
echo "  systemctl --user enable --now quoodle-agent-tray.service"
