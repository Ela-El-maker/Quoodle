#!/bin/bash
set -e

echo "Starting AI Sidecar..."
exec uvicorn app.main:app --host 0.0.0.0 --port "${AI_SIDECAR_PORT:-8000}"

