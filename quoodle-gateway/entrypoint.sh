#!/bin/bash
set -e

echo "Starting Gateway..."

# Start the Telemetry Worker in background
echo "Starting Telemetry Worker..."
python3 app/workers/telemetry_worker.py &
WORKER_PID=$!

# Start FastAPI server
echo "Starting Uvicorn Server..."
# exec replaces the shell process so signals propagate correctly
UVICORN_ARGS=(app.main:app --host 0.0.0.0 --port "${GATEWAY_PORT:-8000}")

if [[ -n "${GATEWAY_TLS_CERT_FILE:-}" && -n "${GATEWAY_TLS_KEY_FILE:-}" ]]; then
  UVICORN_ARGS+=(--ssl-certfile "$GATEWAY_TLS_CERT_FILE" --ssl-keyfile "$GATEWAY_TLS_KEY_FILE")
  if [[ -n "${GATEWAY_TLS_CA_FILE:-}" ]]; then
    UVICORN_ARGS+=(--ssl-ca-certs "$GATEWAY_TLS_CA_FILE")
  fi
  if [[ -n "${GATEWAY_TLS_CERT_REQS:-}" ]]; then
    UVICORN_ARGS+=(--ssl-cert-reqs "$GATEWAY_TLS_CERT_REQS")
  fi
fi

exec uvicorn "${UVICORN_ARGS[@]}"
