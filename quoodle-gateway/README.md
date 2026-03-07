# quoodle-gateway

Real-time WebSocket gateway and command routing broker. Sits between the Control Plane and endpoint agents — verifies signatures, enforces TTL/replay rules, and routes commands.

**Stack:** FastAPI / Python 3.11

## Build & Run

**Prerequisites:** Python 3.11+, Redis

```bash
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Or via Docker from the repo root:

```bash
./scripts/setup_dev.sh
```

### TLS (optional)

Set `GATEWAY_TLS_CERT_FILE`, `GATEWAY_TLS_KEY_FILE`, and optionally `GATEWAY_TLS_CA_FILE`:

```bash
docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d
```

## Configuration

| Variable                    | Purpose                                                |
| --------------------------- | ------------------------------------------------------ |
| `REQUIRE_LARAVEL_SIGNATURE` | Reject unsigned commands from backend (must be `true`) |
| `SIGN_LARAVEL_WEBHOOKS`     | Sign telemetry updates for Control Plane trust         |
| `REQUIRE_ED25519`           | Enforce strict agent message signature verification    |

## API Endpoints

| Method   | Path                                   | Description                              |
| -------- | -------------------------------------- | ---------------------------------------- |
| `GET`    | `/health`                              | Liveness probe with Redis status         |
| `WS`     | `/agent`                               | WebSocket endpoint for agent connections |
| `POST`   | `/api/v1/command/dispatch`             | Dispatch signed commands to agents       |
| `GET`    | `/api/v1/devices/online`               | List connected devices                   |
| `POST`   | `/api/v1/policy/push`                  | Push policy to agents                    |
| `POST`   | `/api/v1/update/deploy`                | Deploy OTA updates                       |
| `POST`   | `/api/v1/webhook/device/paired`        | Register paired device keys              |
| `POST`   | `/api/v1/admin/quarantine/{device_id}` | Quarantine a device                      |
| `DELETE` | `/api/v1/admin/quarantine/{device_id}` | Lift quarantine                          |

## Project Structure

```
app/
├── main.py              # FastAPI app entry point
├── config.py            # Environment configuration
├── api_controller.py    # HTTP route handlers
├── ws/                  # WebSocket protocol handling
└── ...
services/                # Business logic services
tests/                   # Unit and integration tests
```
