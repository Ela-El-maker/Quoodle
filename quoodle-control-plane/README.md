# 🎮 quoodle-control-plane

**Role**: Control / Governance
**Tech Stack**: Laravel (PHP 8.4+)

**Responsibility**: Identity Provider, Certificate Authority (CA), Policy Engine, Audit Log, Compliance Authority.

---

## 📖 Overview

The `quoodle-control-plane` is the **Root of Trust** for the Quoodle system. It is responsible for:

1.  **Identity Management**: Authenticating mobile users (JWT) and issuing device certificates.
2.  **Certificate Authority**: Acting as the intermediate CA to sign device CSRs during pairing.
3.  **Policy Engine**: Defining and signing policy bundles pushed to agents.
4.  **Command Authorization**: Validating user intent and signing command envelopes before dispatch.
5.  **Audit Logging**: Storing a tamper-evident, append-only chain of all system actions (audit-by-default).
6.  **Compliance Authority**: Enforcing compliance and attestation requirements for all endpoints.

Control Plane Architecture (Laravel)
Purpose

The Control Plane is the source of authority:

identity (users, orgs, roles)

device ownership and lifecycle

policy evaluation + compliance decisions

command lifecycle state machine

canonical audit trail

cryptographic signing of commands (intent)

It never talks to the OS. It produces signed intent.

High-level Diagram

┌──────────────────────────────┐
│ Operator UI (Web / Mobile) │
│ - login/MFA │
│ - device list │
│ - issue commands │
│ - view results/audit │
└───────────────┬──────────────┘
│ REST (JWT)
┌───────────────▼──────────────────────────────────────────────┐
│ CONTROL PLANE (Laravel) │
│ │
│ [A] Identity & Access │
│ - users, orgs, roles, permissions │
│ - MFA / session mgmt │
│ │
│ [B] Device Registry │
│ - device lifecycle (paired/active/disabled/quarantined) │
│ - device keys, metadata │
│ │
│ [C] Policy Engine │
│ - allow/deny + reason │
│ - risk tiers + 2FA requirements │
│ - compliance evaluation (attestation, quarantine) │
│ │
│ [D] Command Service (State Machine) │
│ - create command intent │
│ - queue/dispatch state │
│ - ack/result transitions │
│ │
│ [E] Signing Service │
│ - canonical JSON │
│ - sign envelope + attach policy_hash │
│ │
│ [F] Audit + Evidence Store │
│ - immutable audit records │
│ - results + artifacts refs │
└───────────────┬──────────────────────────────────────────────┘
│ Signed HTTPS (to Gateway)
┌───────────────▼──────────────┐
│ Gateway (FastAPI Broker) │
│ - verify signature/TTL/replay│
│ - deliver to agents │
└──────────────────────────────┘
Control Plane “Ins and Outs”
Inputs

From Operator UI:

login / MFA

command requests: device_id, method, params

device lifecycle actions: quarantine, disable, rotate keys

From Gateway (Webhook callbacks):

ACK received

RESULT received

telemetry summaries (optional)

online/offline state (optional)

Outputs

To Operator UI:

device list/status

compliance state and remediation

command timeline + audit trail

results/artifacts

To Gateway:

signed command envelope

optional key distribution updates (device public keys)

webhook verification keys (for gateway → control)

Core Modules (Specific)

1. Identity & Access

Responsibilities:

Users, roles (“operator”, “admin”, “auditor”)

Permission model:

per-method permissions (lock_screen, list_processes, file_read, etc.)

scope constraints (org/team/device group)

MFA policies (step-up auth for sensitive actions)

Outputs used by policy engine:

actor_id

actor_role

auth_strength (mfa level, recent re-auth)

2. Device Registry

Responsibilities:

Device records:

device_id, device_name, hwid

OS, agent version, last_seen

owner/org, tags

Lifecycle state machine:

pending_pair → active → disabled

quarantine overlay state

Device keys:

agent pubkey(s)

rotation history + KIDs

Key idea:

The Control Plane is the root database of device identity.

3. Pairing Service

Responsibilities:

Generate pair_token (short-lived)

Bind pairing request to:

device_name, hwid, agent_pubkey_b64

Confirm pairing:

operator approves (or auto-approve in dev)

returns agent_jwt scoped to that device_id

Security:

Pair tokens short TTL

Device pubkey is “burned in” unless rotated

4. Policy Engine (The Judge)

Responsibilities:

Evaluate intent:

method risk tier

actor permission

device state (active/quarantine)

compliance requirements (attestation, policy_hash match, time window)

Produce decision object:

allow | deny

reason code

requires_2fa

policy_hash (commitment to policy snapshot)

Important: policy_hash is the cryptographic fingerprint of the rule-set used for the decision. That’s how you later prove “we didn’t silently change policy.”

5. Command Service (Lifecycle State Machine)

This is the spine.

States (example):

created

queued (accepted, waiting for delivery)

delivered

acked

completed

failed

expired

rejected (policy denied)

Transitions triggered by:

operator request

gateway delivery events

ack/result webhooks

TTL expiry worker

Guarantees:

Idempotency with client_message_id

Monotonic server sequence for audit ordering

6. Signing Service (The Stamp)

Responsibilities:

Produce canonical JSON envelope:

header: version, timestamp, ttl, requires_ack, priority

meta: device_id, policy_hash, origin_user_id, enc config

body: method, params, sensitive flag

Sign with control plane private key (KID included)

Output:

envelope + signature sent to gateway.

7. Audit & Evidence Store (Immutable Ledger)

Responsibilities:

Record:

who requested what

policy decision and hash

command envelope signature

ack + result signatures

artifact references (URLs/checksums)

Provide queryable audit timeline for UI

Rule:

Audit records are append-only in practice (or WORM-like logic).

Data Model (Minimum, Practical)

users

id, email, role, mfa_enabled, org_id

devices

device_id, hwid, name, os, lifecycle_state, quarantine_state, last_seen

device_keys

device_id, kid, pubkey_b64, created_at, revoked_at

policies

version, hash, rules_json, active

commands

command_id, client_message_id, device_id, actor_id

method, params_json, sensitive

state, reason, ttl_seconds

policy_hash, requires_2fa

created_at, queued_at, completed_at

command_events (audit timeline)

command_id, seq, type (created/delivered/acked/completed/failed)

payload_json, signature, created_at

Control Plane Workers (Background Jobs)

You want 3 workers minimum:

TTL Expirer

marks commands expired when ttl passes

Retry/Timeout Supervisor

flags commands stuck in delivered-without-ack

escalates to UI as “investigate”

Compliance Re-evaluator

periodically re-check device compliance/quarantine state

annotate remediation steps

## 🛠️ Build & Run

### Prerequisites

- PHP 8.4+
- Composer
- MySQL 8.0+
- Redis

### Setup

```bash
# 1. Install dependencies
composer install

# 2. Setup environment
cp .env.example .env
php artisan key:generate

# 3. Migrate database
php artisan migrate

# 4. Generate system keys (Ed25519)
php artisan quoodle:keys:generate
```

### Running

```bash
php artisan serve
```

### TLS (Docker)

For local TLS, use the compose override and provide certs:

```bash
docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d --build
```

Expected cert paths:

- `certs/control-plane.crt`
- `certs/control-plane.key`

## 🔐 Security Context

- **Private Keys**: Stores the CA private key and the Command Signing private key. These must be protected via KMS/HSM in production.
- **Trust**: Trusted by `quoodle-gateway` (via webhook signature) and `quoodle-agent-windows` (via CA chain).

## 📡 API Endpoints

### Authentication & Authorization

- `POST /api/register`: User registration
- `POST /api/login`: User login with JWT
- `POST /api/token/refresh`: Refresh JWT tokens
- `POST /api/logout`: Logout and invalidate tokens
- `POST /api/2fa/setup`: Setup two-factor authentication
- `POST /api/2fa/confirm`: Confirm 2FA setup
- `POST /api/2fa/verify`: Verify 2FA code

### Device Management

- `GET /api/devices`: List all devices (viewer+)
- `GET /api/devices/unpaired`: List unpaired devices
- `GET /api/devices/{device_id}`: Get device details
- `POST /api/devices/{device_id}/claim`: Claim device ownership (operator+)
- `POST /api/devices/{device_id}/rename`: Rename device (operator+)

### Device Pairing

- `POST /api/pair/request`: Request device pairing
- `POST /api/pair/init`: Initialize pairing process
- `POST /api/pair/confirm`: Confirm pairing completion
- `POST /api/pair`: Legacy pairing endpoint
- `POST /api/agent/token`: Generate agent authentication token

### Command Management

- `POST /api/commands`: Execute command on device (operator+)
- `POST /api/command`: Legacy command endpoint
- `GET /api/commands/{command_id}`: Get command status
- `GET /api/devices/{device_id}/commands`: List device commands

### Telemetry & Monitoring

- `GET /api/devices/{device_id}/telemetry/latest`: Get latest telemetry
- `GET /api/devices/{device_id}/telemetry/history`: Get telemetry history

### Updates & OTA

- `GET /api/devices/{device_id}/updates`: List device updates
- `GET /api/devices/{device_id}/updates/{release_id}`: Get update details

### Artifacts

- `POST /api/artifact/request`: Request artifact upload (agent JWT)
- `POST /api/artifact/upload`: Upload artifact (agent JWT)
- `GET /api/artifact/{artifact_id}`: Download artifact

### Audit & Compliance

- `GET /api/audit/device/{device_id}`: Get device audit trail
- `POST /api/audit/append`: Append to audit trail (operator+)
- `GET /api/compliance/profiles`: List compliance profiles
- `POST /api/compliance/evaluate`: Evaluate compliance (operator+)

### Alerts

- `GET /api/alerts`: List alerts
- `POST /api/alerts/{alert_id}/ack`: Acknowledge alert (operator+)

### Policy Management (Admin Only)

- `POST /api/policy/evaluate`: Evaluate policy
- `POST /api/policy/validate_bundle`: Validate policy bundle
