# 🔌 quoodle-gateway

**Role**: Transport / Gateway
**Tech Stack**: FastAPI (Python 3.11+)

**Responsibility**: Real-time WSS Hub, Command Dispatcher, Telemetry Ingestion, Compliance Enforcement, Audit Logging.

---

## 📖 Overview

The `quoodle-gateway` acts as the high-performance edge for the system. It maintains persistent WebSocket connections with thousands of agents and routes messages between the Control Plane and the Agents.

It does **not** make policy decisions; it enforces routing rules, validates signatures, enforces compliance (TTL, anti-replay), and logs all actions for audit.

## Gateway Architecture (FastAPI Broker)

Purpose

The gateway is a transport and enforcement broker between:

Control Plane (Laravel): issues signed intent (commands)

Agents (Linux/Windows): execute locally and return signed results

It must be:

OS-agnostic

stateless where possible

strict about replay/TTL/auth

excellent at routing and observability

## High-level Diagram

┌──────────────────────────────┐
│ Control Plane (Laravel) │
│ - Auth/users/roles/policy │
│ - Signs command envelopes │
└───────────────┬──────────────┘
│ HTTPS (signed payload)
│
┌───────────────▼──────────────────────────────────────────────┐
│ GATEWAY (FastAPI) │
│ │
│ [A] HTTP Ingest API (Control → Gateway) │
│ - verify control signature │
│ - enforce TTL + anti-replay │
│ - persist command state + enqueue │
│ │
│ [B] WebSocket Hub (Gateway ↔ Agents) │
│ - authenticate agent (JWT + device_id) │
│ - maintain connection registry │
│ - push commands + receive ACK/RESULT │
│ │
│ [C] Queue + Delivery Engine │
│ - offline buffering (Redis) │
│ - per-device ordering │
│ - retry + dead-letter │
│ │
│ [D] Result Intake + Forwarder │
│ - verify agent result receipts │
│ - store result + forward to control plane webhook │
│ │
│ [E] Telemetry + Observability │
│ - heartbeat, health, metrics, tracing, audit logs │
└───────────────┬──────────────────────────────────────────────┘
│ Webhooks / signed callbacks
┌───────────────▼──────────────┐
│ Control Plane Webhook │
│ - updates command lifecycle │
│ - audit + compliance view │
└──────────────────────────────┘
Gateway “Ins and Outs”
Inputs

From Control Plane (HTTP):

Signed command envelope (canonical JSON)

metadata: command_id, device_id, ttl_seconds, requires_ack, policy_hash

From Agent (WSS):

AUTH handshake + heartbeat

ACK

RESULT (optionally: artifact references)

telemetry events

Outputs

To Agent (WSS):

COMMAND envelope (signed by control plane, verified by agent)

To Control Plane (webhook/HTTP):

delivery receipts (accepted/rejected)

ACK received

RESULT received

telemetry summaries

Internal Modules (Concrete)

1. HTTP Ingest API (Control → Gateway)

Responsibilities:

Verify control plane signatures (controller pubkey)

Validate schema (strict)

Enforce:

TTL window

replay protection

required fields

Persist minimal command record

Enqueue for delivery

Critical rules:

Never modify command body (only add broker metadata)

Reject if:

signature invalid

TTL expired

command_id replayed

policy_hash missing/malformed

2. WebSocket Hub (Agents)

Responsibilities:

Maintain in-memory connection registry:

device_id → connection

session metadata (ip, connected_at, agent_version)

Authenticate agent:

device_id exists

agent JWT valid (or token scheme)

bind JWT subject to device_id

Track liveness:

ping/pong heartbeat

idle timeout

Backpressure:

per-connection send queue

drop/close on overload

Hard requirements:

One active session per device_id (or explicit multi-session policy)

Connection epoch tracking so stale sessions can’t ack new commands

3. Queue + Delivery Engine

Responsibilities:

Queue commands per-device (ordering guarantee)

If device online: deliver immediately

If offline: store in Redis (or DB) until:

TTL expires

delivered

dead-letter after retry budget

Design details:

Keyed by device:

queue:{device_id}

State machine:

queued → delivered → acked → completed

Retries:

only retry delivery if not acked

never re-execute completed commands

4. Result Intake + Verification

Responsibilities:

Validate agent RESULT/ACK message schema

Verify result receipts / signatures (agent public key or device key)

Attach to command record

Forward to control plane webhook

Critical:

The gateway shouldn’t “believe” results blindly.

At minimum: validate that the result is from the correct authenticated device session.

5. Anti-Replay + TTL Guard (Broker-side)

You want two layers:

Gateway replay cache: command_id LRU for fast rejection

Persistent replay store: Redis/DB record of seen ids with TTL

Also enforce:

issued_at sanity window

TTL remaining must be positive at ingest and at delivery time

6. Observability + Audit

You need:

Structured logs for:

ingest accept/reject reason

ws connect/disconnect

delivery attempts

ack/result timing

Metrics:

online devices

command latency percentiles

queue depth per device

rejection counts by reason

Tracing:

propagate command_id across services

Data Model (Minimum viable)

DeviceSession

device_id

session_id

connected_at

agent_version

last_seen

quarantine_state (if applicable)

CommandRecord

command_id

device_id

method

ttl_seconds

policy_hash

state (queued/delivered/acked/completed/failed/expired)

timestamps

ack payload

result payload

error_code/reason

Security Boundaries (Non-negotiables)

Gateway never generates authority

It routes, verifies, enforces TTL/replay

Authority comes from control plane signatures + agent verification

Deny-by-default

Unknown method? reject at ingest (or at least don’t route)

Separate planes

Control plane API key space ≠ Agent channel auth

Rate limiting

protect:

login/auth endpoints

ws handshake floods

command ingest bursts

Quarantine mode

allow device to connect, but block command delivery if:

policy mismatch

attestation missing (if you enforce it)

flagged by control plane

Practical Gateway Milestones (Build Order)

If your lock_screen and list_processes are now working, the gateway next steps that actually matter:

Per-device ordered delivery

strict FIFO for each device

no parallel execution unless explicitly allowed

Robust ACK/RESULT lifecycle

requires_ack logic

delivery retry only before ack

command expiration enforcement

Offline queue

Redis-backed

TTL-aware queue pruning

Artifact pipeline

pre-signed upload/download URLs

checksums + chunking support

store only references in results

Observability and debugging

one “command timeline” view from ingest → completed

## 🛠️ Build & Run

### Prerequisites

- Python 3.11+
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

### TLS (optional)

The gateway can terminate TLS directly when these environment variables are set:

- `GATEWAY_TLS_CERT_FILE`
- `GATEWAY_TLS_KEY_FILE`
- `GATEWAY_TLS_CA_FILE` (optional)
- `GATEWAY_TLS_CERT_REQS` (optional; numeric OpenSSL verify mode)

Example (docker-compose override):

```bash
docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d
```

## 🔐 Configuration

Based on `docs/specs`, the following security settings are critical:

- **`REQUIRE_LARAVEL_SIGNATURE`**: Must be `true` to reject unauthorized commands from the backend.
- **`SIGN_LARAVEL_WEBHOOKS`**: Must be `true` so the Control Plane trusts our telemetry updates.
- **`REQUIRE_ED25519`**: Enforces strict signature verification on all Agent messages.

## 📡 API Endpoints

### Health & Monitoring

- `GET /health`: Liveness probe with Redis connectivity status.

### WebSocket Endpoints

- `WS /agent`: WebSocket endpoint for agent connections (Linux/Windows agents).

### Command Management

- `POST /api/v1/command/dispatch`: Dispatch signed commands to connected agents.
- `GET /api/v1/devices/online`: List all currently connected devices with session info.

### Policy Management

- `POST /api/v1/policy/push`: Push new policy versions to all connected agents.
- `GET /api/v1/policy/state`: Get current policy state and version.

### OTA Updates

- `POST /api/v1/update/deploy`: Deploy OTA updates to connected agents.

### Device Management

- `POST /api/v1/webhook/device/paired`: Register newly paired device public keys.
- `POST /api/v1/admin/device-keys/{device_id}`: Manually upsert device public keys.

### Quarantine Management

- `POST /api/v1/admin/quarantine/{device_id}`: Place device in quarantine.
- `DELETE /api/v1/admin/quarantine/{device_id}`: Lift device quarantine.

### Testing (Development Only)

- `POST /api/v1/test/fault`: Inject faults for testing (when `ENABLE_TEST_ENDPOINTS=true`).
