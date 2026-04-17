# quoodle-gateway

FastAPI gateway for real-time device connectivity and signed command dispatch.

This service is the transport control plane between control-plane intent and endpoint execution.

## 1. Architecture

### 1.1 Core Responsibilities

- terminate and manage agent WebSocket sessions
- maintain authenticated presence state
- accept dispatch requests from control plane
- route envelopes to live device channels
- emit lifecycle and result webhooks back to control plane

### 1.2 Internal Planes

- HTTP plane: dispatch, pairing callbacks, key publication, admin operations
- WS plane: agent sessions, auth, command delivery, ack/result stream
- presence plane: active channel and auth state indexing

## 2. Stack and Why

- Python 3.11 + FastAPI for async I/O and explicit API contracts.
- Uvicorn for efficient ASGI runtime.
- Redis for shared transient state and broker support.

## 3. Protocol Contract

### 3.1 Agent Auth Handshake

1. agent connects to `/agent`
2. agent sends auth payload
3. gateway validates identity/session context
4. authenticated channel registered for dispatch

### 3.2 Dispatch Contract

Input:

- signed envelope from control plane
- device target metadata

Validation:

- envelope structure and required fields
- signature policy according to gateway config
- target device channel availability

Output:

- dispatch accepted or rejected with explicit reason

### 3.3 Result Contract

Agent ack/progress/result events are normalized and forwarded to control plane webhook endpoints.

## 4. Security Strategy

Key controls:

- optional hard requirements for Laravel request signatures
- optional webhook signing to Laravel
- optional Ed25519 enforcement
- strict malformed/stale payload rejection

Recommended non-lab posture:

- keep all signature requirements enabled

## 5. Presence and Lifecycle Semantics

Online means:

- authenticated WS session is active

Offline means:

- authenticated session absent or disconnected

This distinction avoids confusing service-process liveness with transport/auth liveness.

## 6. Local Run

From `quoodle-gateway`:

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Health endpoint:

- `GET /health`

## 7. Docker Run

From repo root:

```powershell
docker compose up -d --build gateway
```

## 8. Project Layout

- `app/main.py`: app startup/wiring
- `app/api_controller.py`: HTTP routes
- `app/ws/`: socket protocol/session handling
- `app/config.py`: environment contract
- `tests/`: gateway behavior and contract tests

## 9. Troubleshooting

### Device Offline While Service Running

- check if agent channel is authenticated and present
- inspect auth failures in gateway logs
- verify endpoint scheme compatibility (`ws` vs `wss` and TLS support)

### Commands Not Delivering

- verify control plane dispatch call reached gateway
- verify target device channel exists
- verify signature requirements are aligned between services

### Signature/Key Drift

- verify key publication endpoint value
- verify control plane signing key and agent verifier key chain coherence

## 10. Sequence Diagrams

### 10.1 Agent Session Authentication

```text
Agent Runtime        Gateway WS          Presence Index
     |                   |                    |
     | connect /agent    |                    |
     |------------------>|                    |
     | auth payload      | verify token       |
     |------------------>|                    |
     | auth_ok/auth_err  |                    |
     |<------------------| mark session       |
     |                   |------------------->|
```

### 10.2 Dispatch and Result Relay

```text
Control Plane        Gateway HTTP/WS        Agent Runtime       Control Webhook
     |                     |                    |                    |
     | POST dispatch       |                    |                    |
     |-------------------->| send envelope      |                    |
     |                     |------------------->| execute            |
     |                     |<-------------------| ack/result         |
     |                     | POST webhook       |                    |
     |<--------------------|------------------->|                    |
```
