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

### run_windows_ring0_e2e.ps1

Primary Windows ring0 end-to-end runner validating control plane -> gateway -> agent -> kernel.

```bash
pwsh ./scripts/run_windows_ring0_e2e.ps1 -KeepAgentRunning
```

Validates: pairing, WebSocket auth, command signing/delivery, kernel response verification, and telemetry/audit loop.

Logs output to `logs/e2e/`.

### install_linux_agent_systemd.sh

Install and run the Linux agent services.

```bash
./scripts/install_linux_agent_systemd.sh
sudo systemctl daemon-reload
sudo systemctl restart quoodle-privileged quoodle-agent
```

### test_telemetry_worker.sh

Individual endpoint tests.

```bash
./scripts/test_telemetry_worker.sh
```

## Environment Variables

```bash
LARAVEL_BASE_URL=http://localhost:8088
FASTAPI_BASE_URL=http://localhost:8000
TEST_USER_EMAIL=test@example.com
TEST_USER_PASSWORD=password
```
