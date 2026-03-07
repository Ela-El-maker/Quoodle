#!/bin/bash
set -e

# setup_dev.sh - One-click setup for Quoodle Development Environment

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   Quoodle Dev Environment Setup          ${NC}"
echo -e "${GREEN}==========================================${NC}"

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed.${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    # Start checking for "docker compose" V2 plugin
    if ! docker compose version &> /dev/null; then
        echo -e "${RED}Error: docker-compose or docker compose plugin not found.${NC}"
        exit 1
    fi
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

echo -e "${YELLOW}[1/5] Checking configuration files...${NC}"

# Laravel .env
if [ ! -f "quoodle-control-plane/.env" ]; then
    echo "Creating Laravel .env from example..."
    cp quoodle-control-plane/.env.example quoodle-control-plane/.env 2>/dev/null || touch quoodle-control-plane/.env
    # We rely on defaults in compose, but good to have file
fi

# Gateway .env
if [ ! -f "quoodle-gateway/.env" ]; then
    echo "Creating Gateway .env..."
    touch quoodle-gateway/.env
fi

echo -e "${YELLOW}[2/5] Generating Development Keys (Ed25519)...${NC}"
# In a real setup, we'd generate keys here.
# For now, we'll placeholder this or rely on defaults.
echo "Skipping key generation (using defaults or placeholders for now)."

echo -e "${YELLOW}[3/5] Building and Starting Containers...${NC}"
$DOCKER_COMPOSE up -d --build

echo -e "${YELLOW}[4/5] Verifying Health...${NC}"
echo "Waiting for services to become healthy..."
sleep 10
$DOCKER_COMPOSE ps

echo -e "${YELLOW}[5/5] Configuring Linux agent services (optional)...${NC}"
if command -v sudo &> /dev/null; then
    sudo -v >/dev/null 2>&1 || true

    if ! getent group quoodle-agent >/dev/null 2>&1; then
        sudo groupadd --system quoodle-agent || true
    fi
    if ! id -u quoodle-agent >/dev/null 2>&1; then
        sudo useradd --system --no-create-home --shell /usr/sbin/nologin --gid quoodle-agent quoodle-agent || true
    fi

    sudo mkdir -p /opt/quoodle-agent/bin /etc/quoodle /var/lib/quoodle-agent/state /run/quoodle
    sudo chown -R quoodle-agent:quoodle-agent /var/lib/quoodle-agent/state /run/quoodle || true

    if [ -f "quoodle-agent-linux/systemd/quoodle-agent.service" ]; then
        sudo cp quoodle-agent-linux/systemd/quoodle-agent.service /etc/systemd/system/quoodle-agent.service
    fi
    if [ -f "quoodle-agent-linux/systemd/quoodle-privileged.service" ]; then
        sudo cp quoodle-agent-linux/systemd/quoodle-privileged.service /etc/systemd/system/quoodle-privileged.service
    fi

    if [ -f "quoodle-agent-linux/systemd/secrets.env.example" ] && [ ! -f "/etc/quoodle/secrets.env" ]; then
        sudo cp quoodle-agent-linux/systemd/secrets.env.example /etc/quoodle/secrets.env
    fi

    if [ -f "/etc/systemd/system/quoodle-agent.service" ]; then
        sudo sed -i 's|Environment=QUOODLE_WS_URL=.*|Environment=QUOODLE_WS_URL=ws://localhost:8000/agent|' /etc/systemd/system/quoodle-agent.service || true
    fi

    if systemctl is-active --quiet quoodle-agent 2>/dev/null; then
        sudo systemctl stop quoodle-agent || true
    fi
    if systemctl is-active --quiet quoodle-privileged 2>/dev/null; then
        sudo systemctl stop quoodle-privileged || true
    fi

    if [ -f "quoodle-agent-linux/build/agent/quoodle-agent-linux" ]; then
        sudo cp quoodle-agent-linux/build/agent/quoodle-agent-linux /opt/quoodle-agent/bin/
    fi
    if [ -f "quoodle-agent-linux/build/privileged/quoodle-privileged-daemon" ]; then
        sudo cp quoodle-agent-linux/build/privileged/quoodle-privileged-daemon /opt/quoodle-agent/bin/
    fi

    if [ -f "/opt/quoodle-agent/bin/quoodle-agent-linux" ] && [ -f "/opt/quoodle-agent/bin/quoodle-privileged-daemon" ]; then
        sudo systemctl daemon-reload
        sudo systemctl reset-failed quoodle-agent || true
        sudo systemctl reset-failed quoodle-privileged || true
        echo -e \"${YELLOW}Linux agent services installed but not started.${NC}\"
        echo -e \"${YELLOW}Start manually with: sudo systemctl start quoodle-privileged && sudo systemctl start quoodle-agent${NC}\"
    else
        echo -e "${YELLOW}Agent binaries not found; build quoodle-agent-linux first to enable services.${NC}"
    fi
else
    echo -e "${YELLOW}sudo not available; skipping Linux agent service setup.${NC}"
fi

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   Setup Complete!                        ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "Control Plane (Laravel): http://localhost:${QUOODLE_CONTROL_PLANE_PORT:-8088}"
echo -e "Gateway (FastAPI):       http://localhost:8000"
echo -e "Database (MySQL):        localhost:${QUOODLE_DB_PORT:-3308}"
echo -e "Redis:                   localhost:6380"
echo -e "Local Admin Email:       ${DEV_ADMIN_EMAIL:-admin@quoodle.com}"
echo -e "Local Admin Password:    ${DEV_ADMIN_PASSWORD:-password}"
echo ""
echo -e "To stop: $DOCKER_COMPOSE down"
