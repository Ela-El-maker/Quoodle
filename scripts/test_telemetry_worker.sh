#!/bin/bash
# test_telemetry_worker.sh - Verify Telemetry Worker Logic

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export PYTHONPATH="$PROJECT_ROOT/quoodle-gateway"
WORKER_SCRIPT="$PROJECT_ROOT/quoodle-gateway/app/workers/telemetry_worker.py"
LOG_FILE="worker_test.log"

echo "---------------------------------------------------"
echo "Starting Telemetry Worker in background..."
echo "---------------------------------------------------"
python3 "$WORKER_SCRIPT" > "$LOG_FILE" 2>&1 &
WORKER_PID=$!

echo "Worker PID: $WORKER_PID"
sleep 2

echo "---------------------------------------------------"
echo "Checking logs for startup..."
echo "---------------------------------------------------"
if grep -q "Telemetry Worker starting" "$LOG_FILE"; then
    echo "✅ Worker started successfully"
else
    echo "❌ Worker failed to start"
    cat "$LOG_FILE"
    kill $WORKER_PID
    exit 1
fi

echo "---------------------------------------------------"
echo "Verify redis fallback warning..."
echo "---------------------------------------------------"
if grep -q "THIS IS NOT FOR PRODUCTION" "$LOG_FILE"; then
    echo "✅ Production warning found"
else
    echo "❌ Missing production warning (Check redis_service.py modification)"
fi

echo "---------------------------------------------------"
echo "Stopping Worker..."
echo "---------------------------------------------------"
kill $WORKER_PID
wait $WORKER_PID 2>/dev/null

echo "Logs available in: $LOG_FILE"
rm "$LOG_FILE"
