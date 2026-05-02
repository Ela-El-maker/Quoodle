#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run as root (or with sudo)." >&2
  exit 1
fi

TARGET_USER="${SUDO_USER:-root}"

echo "[1/6] Updating apt metadata..."
apt-get update -y

echo "[2/6] Installing base packages..."
apt-get install -y ca-certificates curl gnupg lsb-release ufw git

echo "[3/6] Installing Docker Engine + Compose plugin..."
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
fi

ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME}")"
echo \
  "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[4/6] Enabling Docker service..."
systemctl enable docker
systemctl start docker

if id -u "$TARGET_USER" >/dev/null 2>&1 && [[ "$TARGET_USER" != "root" ]]; then
  echo "[5/6] Adding ${TARGET_USER} to docker group..."
  usermod -aG docker "$TARGET_USER"
else
  echo "[5/6] Skipping docker group assignment for user '${TARGET_USER}'."
fi

echo "[6/6] Configuring firewall (UFW)..."
ufw allow OpenSSH
ufw allow 3000/tcp
ufw allow 8088/tcp
ufw allow 8000/tcp
ufw --force enable

cat <<'EOF'

Bootstrap complete.

Next steps:
1. Re-login to refresh docker group permissions (if non-root user was updated).
2. Copy .env.do-mini.example to .env.do-mini and fill all placeholders.
3. Run: ./scripts/preflight_do_mini.sh .env.do-mini docker-compose.do-mini.yml
4. Deploy: docker compose --env-file .env.do-mini -f docker-compose.do-mini.yml up -d --build

EOF
