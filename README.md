# Quoodle

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-yellow.svg)]()
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-blue.svg)]()
[![Backend: Laravel](https://img.shields.io/badge/Backend-Laravel%2012-red.svg)]()
[![Gateway: FastAPI](https://img.shields.io/badge/Gateway-FastAPI-009688.svg)]()
[![Mobile: Flutter](https://img.shields.io/badge/Mobile-Flutter-02569B.svg)]()
[![Crypto: Ed25519](https://img.shields.io/badge/Crypto-Ed25519-black.svg)]()

Quoodle is a zero-trust remote device operations platform built around explicit identity, signed command envelopes, auditable dispatch, and resilient endpoint runtimes.

## 1. System Thesis

Quoodle is designed around one rule: control is valid only when identity, authorization, and cryptographic proof align at every hop.

That creates three architectural pillars:

- Control authority is centralized in the control plane.
- Execution authority is decentralized to endpoint agents plus privileged boundaries.
- Transport is stateless enough to recover quickly, but stateful enough to preserve traceability.

## 2. Architecture Deep Dive

### 2.1 Logical Planes

- Control Plane: Laravel API, auth, RBAC, pairing, policy, audit persistence.
- Dispatch Plane: FastAPI gateway for WebSocket sessions, command fanout, presence, and webhook relay.
- Execution Plane: Windows/Linux agents, kernel guard or privileged daemon, command handlers.
- Experience Plane: Web console and mobile app for operators/viewers.

### 2.2 Runtime Topology

`Web UI / Mobile -> Control Plane API -> Gateway -> Agent Runtime -> Kernel/Privileged Layer`

`Kernel/Agent Result -> Gateway Webhook -> Control Plane -> UI Surfaces`

### 2.3 Trust Boundaries

- Boundary A: User identity boundary at login/session issuance.
- Boundary B: Role boundary (viewer/operator/admin).
- Boundary C: Device ownership boundary (pairing + confirm).
- Boundary D: Command integrity boundary (Ed25519 signature verification).
- Boundary E: Privilege boundary (user-mode agent to kernel/privileged daemon).

## 3. Component Map and Stack Strategy

| Component | Stack | Design Role | Why This Stack |
| --- | --- | --- | --- |
| `quoodle-control-plane` | PHP 8.4, Laravel 12, MySQL, Redis | Authority and policy source of truth | Mature auth/RBAC ecosystem, queue support, fast CRUD iteration |
| `quoodle-gateway` | Python 3.11, FastAPI, Uvicorn, Redis | Low-latency WS fanout and dispatch broker | Excellent async I/O profile and predictable API contracts |
| `quoodle-control-plane-ui` | Next.js 16, React 19, TypeScript | Operator/viewer web console | Strong routing, SSR/CSR balance, API composition flexibility |
| `quoodle-mobile-client` | Flutter, Riverpod, GoRouter, Dio | Mobile operations and pairing | Single codebase for Android/iOS with robust state tooling |
| `quoodle-agent-windows` | C++23, Win32/Service APIs, named pipes | Durable endpoint runtime on Windows | Performance, low-level OS integration, service reliability |
| `quoodle-agent-linux` | C++17/C + Python tooling | Durable endpoint runtime on Linux | Native integration + practical operational tooling |
| `quoodle-kernel-guard` | KMDF C/C++ (Windows), privileged service (Linux) | Privileged execution boundary | Minimal trusted computing surface for sensitive actions |

## 4. Protocol and Contract Model

### 4.1 Command Envelope Contract

Envelope intent:

- `header`: protocol version, TTL, priority, timestamp, ack requirements.
- `meta`: device identity, policy hash, origin user identity, encryption metadata.
- `body`: method and params.
- `sig`: detached signature over canonical envelope content.

Key guarantees:

- command tamper detection
- replay window control (TTL + timestamp)
- versioned contract evolution
- auditable provenance (`origin_user_id`, trace IDs)

### 4.2 WebSocket Agent Session Contract

Agent session stages:

1. Connect to `/agent`.
2. Authenticate with device identity + JWT context.
3. Receive dispatch envelopes.
4. Send ack/progress/result events.
5. Maintain heartbeat/presence.

Delivery semantics:

- control->gateway is durable through queue/retry.
- gateway->agent is best-effort over live channel with explicit failure reasons.
- result return is idempotent at storage layer.

### 4.3 Pairing Contract

Pairing sequence:

1. Pair session initialized (token or QR payload).
2. Agent proves possession and receives staged runtime credentials.
3. User confirms ownership with device name + device-id suffix challenge.
4. Role transitions (viewer -> operator) and command authority unlock.

## 5. Design Patterns Used

### 5.1 Service-First Endpoint Pattern

On Windows and Linux, the background service is the source of truth. UI processes are observers/controllers only.

Benefits:

- endpoint continuity after user logoff
- predictable recovery under crash conditions
- strict separation between persistence/runtime and presentation

### 5.2 CQRS-Style Command Path

Commands are treated as explicit write actions with separate read projections for UI trace/result views.

Benefits:

- clean auditability
- simpler retries and replay-safe updates
- UI performance through projection-friendly models

### 5.3 Policy-as-Data Pattern

Policy context rides in envelopes (`policy_hash`, version) and is validated at execution edge.

Benefits:

- deterministic drift detection
- explicit policy provenance in traces
- safer staged policy rollout

### 5.4 Adapter Boundary Pattern

Kernel operations and privileged functions are invoked through narrow adapters rather than exposing raw OS internals to business logic.

Benefits:

- reduced blast radius
- easier testing with mocks/fakes
- protocol evolution without rewriting domain logic

## 6. State Machines (Operational)

### 6.1 Device Lifecycle

- `unclaimed`
- `pending_pairing`
- `paired_pending_confirm`
- `online_authenticated`
- `offline`

### 6.2 Command Lifecycle

- `accepted`
- `queued`
- `dispatched`
- `executing`
- `completed` or `failed`

Failure reasons are explicit (`device_not_connected`, `signature_invalid`, handler-specific errors).

## 7. Security Architecture

- Ed25519 signatures for command authenticity and integrity.
- JWT-based device session authentication.
- Ownership challenge before elevated control.
- Kernel/privileged boundaries for sensitive operations.
- Trace IDs across every hop for forensic reconstruction.
- Role-gated UX and API access.

## 8. Reliability Strategy

- Auto-start endpoint services via SCM/systemd.
- Recovery actions for service crashes.
- Identity reconciliation at runtime to reduce stale pairing drift.
- Adaptive polling + event-driven updates in UI layers.
- Queue-backed dispatch from control plane to gateway.

## 9. Local Bring-Up (Reference)

### 9.1 Backend Core

```powershell
cd C:\Users\felix\Work-Force\Quoodle
Copy-Item .env.example .env -Force
docker compose --env-file .env up -d --build
docker compose ps
```

### 9.2 Windows Agent

```powershell
cd .\quoodle-agent-windows
# Build agent
# Install service
# Build ui-companion
# Pair from UI
```

Use component READMEs below for exact commands and expected outputs.

## 9.3 Production Deployment

For production-ready, decoupled deployment (separate web/scheduler/worker roles, external DB/Redis, and preflight checks), use:

- [Production Deployment Runbook](docs/deployment.md)
- [DigitalOcean Mini Ubuntu Runbook](docs/deployment-do-mini.md)

## 10. Verification Strategy

### 10.1 Fast Smoke

- login as viewer
- pair device (token or QR)
- confirm ownership
- verify device becomes online
- run `collect_system_info`
- verify trace transitions and result appears

### 10.2 Deep Validation

- restart gateway, ensure reconnect behavior is healthy
- restart agent service, ensure presence recovers
- rotate controller signing key in lab and verify signature safeguards
- validate alert/compliance projections after telemetry updates

## 11. Project READMEs

- [Control Plane](quoodle-control-plane/README.md)
- [Control Plane UI](quoodle-control-plane-ui/README.md)
- [Gateway](quoodle-gateway/README.md)
- [Windows Agent](quoodle-agent-windows/README.md)
- [Windows UI Companion](quoodle-agent-windows/ui-companion/README.md)
- [Linux Agent](quoodle-agent-linux/README.md)
- [Kernel Guard](quoodle-kernel-guard/README.md)
- [Mobile Client](quoodle-mobile-client/README.md)
- [Infra](quoodle-infra/README.md)
- [Scripts](scripts/README.md)
- [Key Utilities](quoodle-scripts/README.md)

## 12. Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## 13. License

[MIT](LICENSE)

## 14. Sequence Diagrams

### 14.1 End-to-End Command Flow

```text
Operator UI/Mobile  Control Plane      Gateway         Agent Service      Kernel/Priv Layer
      |                  |                |                 |                    |
      | POST /commands   |                |                 |                    |
      |----------------->| validate+sign  |                 |                    |
      |                  | enqueue job    |                 |                    |
      |                  |--------------->| dispatch env    |                    |
      |                  |                |---------------->| verify+execute      |
      |                  |                |                 |------IOCTL/UDS---->|
      |                  |                |                 |<-----result---------|
      |                  |<---------------| webhook result  |                    |
      | GET trace/result |                |                 |                    |
      |<-----------------| state updated  |                 |                    |
```

### 14.2 Pairing and Ownership Flow

```text
Viewer/Operator     Control UI/API      Gateway         Agent UI/Service    Device DB
      |                  |                |                    |               |
      | Start Pair       |                |                    |               |
      |----------------->| create session |                    |               |
      |                  |--------------->| pair intent        |               |
      | Enter token/QR   |                |<-------------------| send proof     |
      |----------------->| verify pair    |                    |               |
      | Confirm name+id  |                |                    |               |
      |----------------->| link ownership |                    |------------->  |
      |                  | promote role   |                    |               |
      |<-----------------| operator ready |                    |               |
```
