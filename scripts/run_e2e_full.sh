#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG_DIR="${LOG_DIR:-$ROOT/logs/e2e}"
mkdir -p "$LOG_DIR"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="$LOG_DIR/e2e_${TS}.jsonl"
META_FILE="$LOG_DIR/e2e_${TS}_meta.txt"

LARAVEL_BASE_URL="${LARAVEL_BASE_URL:-http://localhost:8080}"
FASTAPI_BASE_URL="${FASTAPI_BASE_URL:-http://localhost:8000}"
TEST_USER_EMAIL="${TEST_USER_EMAIL:-admin@quoodle.com}"
TEST_USER_PASSWORD="${TEST_USER_PASSWORD:-password}"
RUNS="${RUNS:-3}"
SEED="${SEED:-1337}"

if [ $# -ge 1 ]; then
  RUNS="$1"
fi
if [ $# -ge 2 ]; then
  SEED="$2"
fi

{
  echo "timestamp=${TS}"
  echo "laravel=${LARAVEL_BASE_URL}"
  echo "fastapi=${FASTAPI_BASE_URL}"
  echo "runs=${RUNS}"
  echo "seed=${SEED}"
  echo "user_email=${TEST_USER_EMAIL}"
  if [ -n "${TEST_USER_PASSWORD}" ]; then
    echo "user_password=***"
  fi
} > "$META_FILE"

if command -v docker >/dev/null 2>&1; then
  docker compose ps >> "$META_FILE" 2>&1 || true
fi

echo "Writing logs to ${LOG_FILE}"
LARAVEL_BASE_URL="$LARAVEL_BASE_URL" \
FASTAPI_BASE_URL="$FASTAPI_BASE_URL" \
TEST_USER_EMAIL="$TEST_USER_EMAIL" \
TEST_USER_PASSWORD="$TEST_USER_PASSWORD" \
RUNS="$RUNS" \
SEED="$SEED" \
python3 e2e_quoodle_harness.py | tee "$LOG_FILE"
