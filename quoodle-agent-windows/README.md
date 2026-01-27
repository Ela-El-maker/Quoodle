# 💻 quoodle-agent-windows

**Role**: Execution / Enforcement (User Mode)
**Tech Stack**: C++ (WinAPI, Boost.Asio)

**Responsibility**: WSS Client, Command Verification, Telemetry Producer, Audit Logging.

---

## 📖 Overview

The `quoodle-agent-windows` is the user-mode persistent service running on the target device. It is responsible for:

1.  **Transport**: Establishing the mTLS-secured WebSocket to `quoodle-gateway`.
2.  **Verification**: Verifying Ed25519 signatures on all incoming command envelopes.
3.  **Kernel Bridge**: Forwarding validated commands to `quoodle-kernel-guard` via IOCTL.
4.  **Telemetry**: Collecting system metrics and streaming them upstream.
5.  **Audit Logging**: Logging all actions and results for compliance and forensic review.

enforces policy and sequencing
brokers privileged actions via a strict boundary (driver, helper, or OS APIs)

## Windows Agent Service Architecture (User-Mode Authority Gate)

The Windows Agent Service is the OS-adjacent executor that:

- Maintains a secure control channel (WSS)
- Verifies command authenticity and sequencing
- Enforces policy and anti-replay
- Translates "intent" → "capability requests"
- Brokers privileged actions via a strict boundary (driver, helper, or OS APIs)
- Streams telemetry and audit logs

It should run with least privilege, and only escalate through designed choke points.

## Architectural Overview

┌──────────────────────────────────────────────────────────────┐
│ Windows Service Host │
│ (quoodle-agent.exe / service) │
│ - SCM-managed: auto start, recovery │
│ - Runs as dedicated service account (least privileges) │
└───────────────▲───────────────────────────────────────────────┘
│ Config + Secrets (DPAPI / ACL’ed file)
┌───────────────┴───────────────────────────────────────────────┐
│ [1] Bootstrap & Identity │
│ - Load device_id, agent keys, controller pubkey │
│ - Validate config schema │
│ - Initialize local state store (seq, cache) │
└───────────────▲───────────────────────────────────────────────┘
│ WSS (TLS) + Signed envelopes
┌───────────────┴───────────────────────────────────────────────┐
│ [2] Gateway Channel Manager │
│ - Maintain WSS connection / reconnect policy │
│ - Heartbeats + liveness │
│ - Backoff + jitter │
│ - Streams: COMMAND, ACK, RESULT, TELEMETRY │
└───────────────▲───────────────────────────────────────────────┘
│ Incoming signed envelopes
┌───────────────┴───────────────────────────────────────────────┐
│ [3] Crypto & Verification Pipeline │
│ - Verify envelope signature (controller pubkey) │
│ - Verify request_sig / canonical JSON │
│ - Check device_id match │
│ - Check policy_hash / policy_version │
│ - Reject if any mismatch │
└───────────────▲───────────────────────────────────────────────┘
│ Validated command intent
┌───────────────┴───────────────────────────────────────────────┐
│ [4] Replay / TTL / Sequence Guard │
│ - Monotonic seq persisted locally (atomic writes) │
│ - Command ID LRU cache (replay prevention) │
│ - TTL enforcement with local time sanity checks │
└───────────────▲───────────────────────────────────────────────┘
│ Allowed intent → capability request
┌───────────────┴───────────────────────────────────────────────┐
│ [5] Capability Router (deny-by-default) │
│ - method → cap_id mapping │
│ - parameter bounds validation │
│ - risk tier tagging (low/medium/high) │
│ - escalation required? → gate to privileged boundary │
└───────────────▲───────────────────────────────────────────────┘
│ Local execution paths
┌──────────┴───────────┐ ┌──────────┴───────────┐
│ │ │ │
┌────┴────────────────┐ ┌──┴───────────────────┐ ┌──┴───────────────────┐
│ [6A] User-Mode Ops │ │ [6B] Privileged Ops │ │ [6C] Artifact Ops │
│ - sysinfo (WMI) │ │ via Driver IOCTL │ │ - screenshot pipeline│
│ - list processes │ │ or Trusted Helper │ │ - file upload/download│
│ - network status │ │ - lock session │ │ - chunking/checksum │
└────▲─────────────────┘ └──▲───────────────────┘ └──▲───────────────────┘
│ results/notes │ signed receipts │ artifacts/URLs
└──────────┬───────────────┴───────────────┬───────────┘
│ │
┌───────────────┴───────────────────────────────┴───────────────┐
│ [7] Result Composer & Telemetry │
│ - Normalize output schema │
│ - Attach receipts, timings, errors │
│ - Optional artifact upload (gateway pre-signed URL) │
│ - Send RESULT + periodic telemetry │
└───────────────────────────────────────────────────────────────┘

Key Subsystems (What “good” looks like)

1. Bootstrap & Secrets

Goal: never ship secrets loosely.

Recommended:

Store secrets in one file with strict ACLs (service account + SYSTEM only)

Use DPAPI to encrypt private keys at rest (Windows-provided)

Validate env/config on startup and refuse to run if incomplete

2. Gateway Channel Manager (WSS)

Goal: resilience without chaos.

Must include:

exponential backoff + jitter

clean reconnect state machine

heartbeat/keepalive

“connection epoch” tracking (so old messages don’t resurface)

3. Crypto + Verification Pipeline

Goal: the agent doesn’t “trust the network”, it trusts signatures.

Pipeline checks:

envelope signature (controller pubkey)

payload canonical form (to avoid signature ambiguity)

device_id match

policy_hash match

Any mismatch: reject + audit.

4. Replay/TTL/Sequence Guard

Goal: make replay attacks boring.

seq must strictly increase

persist sequence atomically (no “lost updates”)

reject stale TTL

keep LRU cache of recent command_ids

5. Capability Router

Goal: “methods” are a UI concept, “capabilities” are enforcement.

strict method allowlist

parameter validation

risk tier system (for compliance, MFA, approvals)

route privileged actions to boundary only

6. Execution Paths
   6A: User-mode ops (safe-ish)

inventory, sysinfo, process listing, etc.

should be sandboxed and time-limited

6B: Privileged ops (hard boundary)

Two good patterns:

Driver IOCTL for the “point of no return”

Trusted helper (separate exe/service running as SYSTEM) with strict IPC

The agent itself stays least-privileged.

6C: Artifact ops (high bandwidth)

chunking, checksums, retry

metadata and artifact integrity

upload via gateway signed URLs (avoid embedding credentials)

7. Result Composer & Telemetry

Goal: predictable result schema + indisputable audit trail.

always return status + error_code + timestamps

attach receipts from privileged boundary

include “what was attempted vs what happened”

“Ins and Outs” of the Windows Agent
Inputs (from outside)

Signed command envelopes from gateway

Policy hash/version expectations

Optional artifact URLs / upload tokens

Outputs (to outside)

ACK (received + verified)

RESULT (success/fail + receipts)

TELEMETRY (health, version, uptime, compliance posture)

Inputs (local)

config/secrets store

kernel receipts / helper results

OS data sources (WMI, perf counters)

Outputs (local)

event logs (Windows Event Log / ETW)

state store updates (seq, LRU)

Practical Build Milestones (Windows Agent Service)

If lock_screen works now, the next “teachable” and architectural steps are:

Reliable ACK/RESULT lifecycle

requires_ack handling

timeout behavior

retries idempotently

State store correctness

monotonic seq persisted atomically

replay cache

Artifact pipeline

screenshot or file fetch as first “big payload”

chunked upload + checksum + retry

Capability router + param validation

deny-by-default

enforce bounds

Observability

event log + ETW

structured error codes

Hardening

service account + minimal rights

secure config ACLs

DPAPI at rest

## 🛠️ Build & Run

### Prerequisites

- CMake 3.20+
- Visual Studio 2022 (MSVC)
- Boost Libraries
- OpenSSL

### Setup

```bash
mkdir build
cd build
cmake ..
cmake --build . --config Release
```

### Running

```bash
./quoodle-agent-windows.exe --config config.json
```

## 🔐 Security Context

- **Keys**: Generates a unique Ed25519 keypair on first run. Stores private key in Windows DPAPI.
- **Trust**: Only trusts commands signed by the Control Plane's public key (hardcoded or pinned).
