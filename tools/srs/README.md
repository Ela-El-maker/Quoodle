# System Readiness Simulation (SRS)

This folder contains a **"God-Mode"** end-to-end readiness script that simulates:
- a **virtual user** (register/login + 2FA enrollment)
- a **virtual device** (unpaired discovery + claim)
- a **virtual attacker** (missing/wrong 2FA, optional replay attempts)

It prints an **SRS report** with PASS/FAIL/SKIP per hop.

## Run

Prereqs:
- Laravel API running (default assumes `http://localhost:8000/api`)
- FastAPI running (default assumes `http://localhost:8001/api/v1`)

Quick start (common local defaults):

```bash
# Laravel
cd backend-laravel
php artisan serve --host 127.0.0.1 --port 8000

# FastAPI (in another terminal)
cd backend-fastapi
uvicorn app.main:app --host 127.0.0.1 --port 8001
```

From repo root:

```bash
python tools/srs/srs_runner.py
```

Ground-truth / policy verification trace:

```bash
python tools/srs/system_validation_trace.py
```

## Environment variables

Required for the full user journey:
- `SRS_LARAVEL_API_BASE` (default: `http://localhost:8000/api`)
- `SRS_FASTAPI_API_BASE` (default: `http://localhost:8001/api/v1`)

Tip (Windows/MSYS): if `localhost` is flaky, use `127.0.0.1`.

Optional (websocket discovery probe):
- `SRS_FASTAPI_WS` (default: `ws://localhost:8001/agent`)
- Install websocket client: `pip install websockets`

Optional:
- `SRS_EMAIL` (default: `srs@example.com`)
- `SRS_PASSWORD` (default: `Password123!`)
- `SRS_DISPLAY_NAME` (default: `SRS User`)

Optional (enables signature + replay checks against FastAPI control-plane):
- `SRS_LARAVEL_SERVICE_PRIVATE_KEY_B64`

Optional (enables sending a valid FastAPI->Laravel signed webhook):
- `SRS_FASTAPI_SERVICE_PRIVATE_KEY_B64`

Optional (ground-truth verifier timing):
- `STATE_VERIFY_DELAY_SECONDS` (default: 10)

Notes:
- If signature enforcement is disabled in services, the related checks will be reported as **SKIPPED** (not "MET").
- This script is intentionally **fail-closed** in reporting: it won’t claim a pillar is met unless it can prove it by runtime behavior or a static code check.
