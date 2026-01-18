# 🔌 quoodle-gateway

**Role**: Transport / Gateway
**Tech Stack**: FastAPI (Python 3.10+)
**Responsibility**: Real-time WSS Hub, Command Dispatcher, Telemetry Ingestion.

---

## 📖 Overview

The `quoodle-gateway` acts as the high-performance edge for the system. It maintains persistent WebSocket connections with thousands of agents and routes messages between the Control Plane and the Agents.

It does **not** make policy decisions; it enforces routing rules and validates signatures before forwarding.

## 🛠️ Build & Run

### Prerequisites
- Python 3.10+
- Redis

### Setup

```bash
# 1. Create venv
python3 -m venv venv
source venv/bin/activate

# 2. Install dependencies
pip install -r requirements.txt
```

### Running

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## 🔐 Configuration

Based on `docs/specs`, the following security settings are critical:

- **`REQUIRE_LARAVEL_SIGNATURE`**: Must be `true` to reject unauthorized commands from the backend.
- **`SIGN_LARAVEL_WEBHOOKS`**: Must be `true` so the Control Plane trusts our telemetry updates.
- **`REQUIRE_ED25519`**: Enforces strict signature verification on all Agent messages.

## 📡 API Endpoints

- `GET /health`: Liveness probe.
- `WS  /agent`: WebSocket endpoint for `quoodle-agent-windows`.
- `POST /command/dispatch`: Internal hook for Control Plane to push commands.
