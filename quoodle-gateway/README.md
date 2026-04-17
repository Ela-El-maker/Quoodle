# quoodle-gateway

FastAPI gateway for real-time device connectivity and command routing.

Primary functions:

- terminates agent WebSocket connections
- tracks online authenticated device presence
- accepts command dispatch from control plane
- forwards command envelopes to device channels
- returns command ACK/results and device lifecycle events via webhooks

Stack:

- Python 3.11
- FastAPI/Uvicorn
- Redis (presence and broker support)

## 1. Local Run

From `quoodle-gateway`:

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Health endpoint:

- `GET /health`

## 2. Core Endpoints

HTTP:

- `POST /api/v1/command/dispatch`
- `POST /api/v1/policy/push`
- `POST /api/v1/update/deploy`
- `POST /api/v1/webhook/device/paired`
- `GET /api/v1/controller/signing-key`
- admin quarantine endpoints

WebSocket:

- `WS /agent`

## 3. Runtime Data Flow

1. Agent connects to `/agent`.
2. Agent sends auth payload (device identity + JWT/signature context).
3. Gateway validates and marks session presence.
4. Control plane dispatches signed command envelope.
5. Gateway routes envelope to device channel.
6. Agent ACK/result is received and relayed to control plane webhook.

## 4. Security Controls

Config toggles:

- `REQUIRE_LARAVEL_SIGNATURE`
- `SIGN_LARAVEL_WEBHOOKS`
- `REQUIRE_ED25519`

Operational guidance:

- keep signature verification enabled in non-lab environments
- avoid accepting unsigned command or webhook payloads
- reject stale, malformed, or mismatched device envelopes

## 5. Docker Run

From repo root:

```powershell
docker compose up -d --build gateway
```

## 6. Project Layout

- `app/main.py` app startup
- `app/api_controller.py` HTTP API routes
- `app/ws/` WS protocol and state handling
- `app/config.py` env config
- `tests/` unit/integration checks

## 7. Troubleshooting

- device appears offline while service running: verify WS auth success and presence updates
- commands stuck queued: verify dispatch endpoint reached gateway and device channel exists
- signature failures: verify controller public key and envelope signing path
- webhook mismatch: verify shared signing/verification configuration between gateway and control plane
