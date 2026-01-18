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
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
