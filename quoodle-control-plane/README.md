# quoodle-control-plane

Laravel control plane and trust anchor for Quoodle.

This service is the authoritative source for identity, ownership, role permissions, policy, and command acceptance decisions.

## 1. Architecture Strategy

### 1.1 Bounded Contexts

- Auth Context: user accounts, sessions, refresh flow, role derivation.
- Device Context: lifecycle, ownership, pairing state, metadata.
- Command Context: command creation, authorization, signing, dispatch orchestration.
- Audit/Telemetry Context: immutable activity records and operational projections.

### 1.2 Data Ownership Rule

The control plane owns canonical business state. Gateway and agents own transport/runtime state but report back into control plane projections.

## 2. Stack and Why

- PHP 8.4 and Laravel 12 for rapid domain iteration and strong middleware/policy patterns.
- MySQL for transactional and queryable operational history.
- Redis for queues, caching, and transient coordination.

Tradeoff profile:

- favors correctness and auditability over ultra-low-latency writes
- uses async jobs for dispatch fanout to keep API response times stable

## 3. API Design Patterns

### 3.1 Role-Gated Surfaces

API routes are mapped to role scopes:

- viewer: visibility + pairing initiation surfaces
- operator: command and alert workflows
- admin: governance and high-trust controls

### 3.2 Contract-First Command Intake

Command requests are normalized and validated before enqueue:

- method and params contract checks
- device ownership checks
- policy context resolution
- signature payload generation

### 3.3 Idempotent Update Pattern

Webhook and result handlers are designed to tolerate retries without duplicating logical state transitions.

## 4. Core Runtime Flow

1. user authenticates
2. user pairs/claims device
3. command submitted
4. authorization + policy checks
5. signed envelope created
6. dispatch job enqueued
7. gateway dispatches to active channel
8. ack/result webhooks update command timeline
9. UI projections show trace and outcome

## 5. Protocol and Signing Strategy

### 5.1 Envelope Composition

Envelope includes:

- protocol header (version, timestamp, ttl, priority)
- meta (device, policy hash, origin)
- body (method, params, sensitive flag)
- detached signature (`sig`)

### 5.2 Signing Separation

Control plane signs dispatch intent; agent verifies locally. This prevents trust-on-transport and blocks tampering between services.

### 5.3 Time-Bound Validity

TTL and timestamp constraints reduce replay and stale command risk.

## 6. Pairing and Ownership Model

### 6.1 Intent

Pairing grants a user operational control over a specific runtime identity.

### 6.2 Steps

- pair session creation
- token/QR proof flow
- pending device detection
- ownership confirmation challenge
- device link persistence
- role elevation where applicable

## 7. Security Model

- strict RBAC checks before command acceptance
- signed envelope requirement for gateway dispatch path
- audit trails on user actions and command lifecycle transitions
- explicit ownership link required for device control

## 8. Project Layout

- `app/Http/Controllers/`: request entry points
- `app/Jobs/`: async dispatch and workflow jobs
- `app/Services/`: domain services (pairing, dispatch, security)
- `app/Models/`: persistence models
- `routes/`: route groups and middleware boundaries
- `database/migrations/`: schema and lifecycle evolution
- `tests/`: contract and regression tests

## 9. Local Run

From `quoodle-control-plane`:

```powershell
composer install
Copy-Item .env.example .env -Force
php artisan key:generate
php artisan migrate
php artisan serve --host=0.0.0.0 --port=8088
```

Recommended: run from repo-root `docker compose` for full system integration.

## 10. Testing Strategy

```powershell
php artisan test
```

Useful focus suites:

```powershell
php artisan test --filter Pair
php artisan test --filter Command
php artisan test --filter Auth
```

## 11. Troubleshooting

### Auth Loops

- verify `/api/auth/me` responses and cookie settings
- verify refresh token lifecycle

### Commands Stuck Queued

- verify queue worker health
- inspect failed jobs and dispatch job logs
- verify gateway reachability and device online state

### Signature Issues

- verify signing keys are consistent across control plane, gateway endpoint publication, and agent verification inputs

## 12. Sequence Diagrams

### 12.1 Command Acceptance and Dispatch

```text
Web/Mobile UI      Controller/API     Policy Layer      Queue Worker      Gateway
     |                  |                 |                |               |
     | POST /commands   |                 |                |               |
     |----------------->| normalize req   |                |               |
     |                  |------authorize->| allow/deny     |               |
     |                  |<----------------|                |               |
     |                  | create envelope |                |               |
     |                  | enqueue job     |                |               |
     |                  |--------------------------------->| dispatch HTTP |
     |                  |                 |                |-------------->|
```

### 12.2 Pair Confirm and Ownership Link

```text
User UI            Pairing API         Devices Service        DB
  |                    |                     |                |
  | pair/confirm       | validate challenge  |                |
  |------------------->|-------------------->| link user<->dev|
  |                    |                     |--------------->|
  |                    | role update result  |                |
  |<-------------------|                     |                |
```
