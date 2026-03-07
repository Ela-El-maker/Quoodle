# scripts

Development, testing, and deployment automation for Quoodle.

## Setup

### setup_dev.sh

One-click setup for the complete development environment.

```bash
./scripts/setup_dev.sh
```

Creates `.env` files, builds containers (Laravel, FastAPI, MySQL, Redis), runs migrations, and verifies health.

| Service | URL |
|---|---|
| Control Plane | http://localhost:8088 |
| Gateway | http://localhost:8000 |
| MySQL | localhost:3307 |
| Redis | localhost:6379 |

## Testing

### run_e2e_full.sh

End-to-end test runner validating the complete protocol loop.

```bash
./scripts/run_e2e_full.sh [runs] [seed]
```

Validates: registration, pairing, WebSocket auth, command signing/delivery, telemetry, and audit integrity.

Logs output to `logs/e2e/`.

### setup_linux_agent_secrets.py

Pair the real Linux host agent and generate its secrets file.

```bash
python3 ./scripts/setup_linux_agent_secrets.py

# Deploy to the installed service
sudo cp ~/.config/quoodle/secrets.env /etc/quoodle/secrets.env
sudo systemctl daemon-reload
sudo systemctl restart quoodle-privileged quoodle-agent
```

### test_api_auth.sh / test_telemetry_worker.sh

Individual endpoint tests.

```bash
./scripts/test_api_auth.sh
./scripts/test_telemetry_worker.sh
```

## Environment Variables

```bash
LARAVEL_BASE_URL=http://localhost:8088
FASTAPI_BASE_URL=http://localhost:8000
TEST_USER_EMAIL=test@example.com
TEST_USER_PASSWORD=password
```
