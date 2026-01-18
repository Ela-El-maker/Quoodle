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

echo -e "${YELLOW}[1/4] Checking configuration files...${NC}"

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

echo -e "${YELLOW}[2/4] Generating Development Keys (Ed25519)...${NC}"
# In a real setup, we'd generate keys here.
# For now, we'll placeholder this or rely on defaults.
echo "Skipping key generation (using defaults or placeholders for now)."

echo -e "${YELLOW}[3/4] Building and Starting Containers...${NC}"
$DOCKER_COMPOSE up -d --build

echo -e "${YELLOW}[4/4] Verifying Health...${NC}"
echo "Waiting for services to become healthy..."
sleep 10
$DOCKER_COMPOSE ps

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   Setup Complete!                        ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "Control Plane (Laravel): http://localhost:8080"
echo -e "Gateway (FastAPI):       http://localhost:8000"
echo -e "Database (MySQL):        localhost:3307"
echo -e "Redis:                   localhost:6379"
echo ""
echo -e "To stop: $DOCKER_COMPOSE down"
