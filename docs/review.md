# Quoodle System Review

This review summarizes the Quoodle system as represented in the repository docs and code layout. It focuses on architecture, responsibilities, trust boundaries, data flows, interfaces, and explicitly stated gaps. It does not include runtime verification or deployment validation.

## 1) System Overview
Quoodle is a research-grade Secure Device Control System that simulates high-assurance EMM/EDR behavior for Windows endpoints. It is designed around strict cryptographic verification and a separation of policy (control plane) from transport (gateway) and execution (agent + kernel).

Primary goals:
- Demonstrate end-to-end integrity for remote commands.
- Provide a reference implementation for Zero Trust device control patterns.
- Maintain modular components that scale and evolve independently.

## 2) Core Components and Responsibilities

### quoodle-mobile-client (Flutter)
What it is:
- User-facing UI for authentication, pairing, device browsing, command issuance, telemetry viewing, and updates.
- Connects to Control Plane over HTTPS and to Gateway (WSS/push) for real-time features.

What it is not:
- Not a root of trust.
- Not a policy decision maker.
- Not a privileged executor.

### quoodle-control-plane (Laravel)
What it is:
- Root of trust: CA, command signing authority, and identity provider.
- Policy engine and audit logging system.
- API surface for admin and user actions (commands, devices, telemetry, alerts, policies).
- Issues certificates and JWTs.

What it is not:
- Not a WebSocket hub.
- Not responsible for device execution or direct connectivity.
- Not a device telemetry ingest pipeline.

### quoodle-gateway (FastAPI)
What it is:
- WebSocket control channel (WSS) for large numbers of agents.
- Dispatches signed commands from Control Plane to agents.
- Ingests telemetry and forwards to Redis/worker pipelines.
- Publishes webhooks back to the Control Plane.

What it is not:
- Not a signing authority.
- Not a policy engine.
- Not the system of record for persistent device state.

### quoodle-agent-windows (C++ Windows Service)
What it is:
- Persistent device agent running as a Windows service.
- Manages WSS connection to Gateway.
- Verifies signatures on commands and forwards to the kernel service.
- Produces telemetry and heartbeats.

What it is not:
- Not a privileged executor of sensitive OS actions.
- Not a policy authority.
- Not a full OS management plane on its own.

### quoodle-kernel-guard (Windows Kernel Driver/Service)
What it is:
- Privileged execution layer (Ring 0) for sensitive actions.
- Enforces an opcode allowlist and verifies IOCTL signatures.
- Supports tamper resistance and attestation (simulated).

What it is not:
- Not network-facing.
- Not a policy engine.
- Not a full EDR kernel suite or rootkit.

### quoodle-infra (DevOps)
What it is:
- Docker Compose, Kubernetes, Terraform, and monitoring configuration.
- CI/CD workflows for gateway, control plane, agent, and mobile builds.

What it is not:
- Not a managed production SaaS environment.
- Not a full enterprise deployment runbook.

## 3) Trust Model and Security

### Root of Trust
- The Control Plane is the root of trust: it holds CA keys and command signing keys.
- Compromise of Control Plane private keys is a catastrophic, system-wide compromise.

### Cryptography and Integrity
- Ed25519 signatures for commands and kernel IOCTL requests.
- Canonical JSON signing conventions for deterministic signatures.
- Sequence numbers and timestamps to mitigate replay attacks.

### Transport Security
- TLS/WSS between agents and gateway; mTLS is specified for production.
- HTTPS for mobile to control plane traffic.

### Key Management (documented intent)
- CA keys stored in KMS/HSM (target architecture).
- Agent keys stored via Windows DPAPI.
- Kernel verification keys are embedded at build time.

## 4) System Flows

### Pairing and Enrollment
1. Agent produces a pairing token (QR).
2. Mobile client scans and submits to Control Plane.
3. Control Plane validates, issues device identity and certificate.
4. Agent uses device certificate to establish WSS/mTLS with Gateway.

### Command Lifecycle
1. User issues command via mobile client.
2. Control Plane enforces policy and signs a command envelope.
3. Gateway delivers the signed command to the agent via WSS.
4. Agent verifies signature and sends to kernel via IOCTL.
5. Kernel executes opcode and returns signed result.
6. Result returns to Gateway and then to Control Plane/mobile via webhooks.

### Telemetry Pipeline
1. Agent collects telemetry and sends to Gateway via WSS.
2. Gateway writes telemetry to Redis streams.
3. Workers persist/aggregate telemetry in MySQL via Control Plane.

## 5) Interfaces and Protocols

### WebSocket Protocol
- Common envelope with fields such as type, device_id, session_id, timestamp, message_id, body, sig.
- Message types: AUTH, AUTH_ACK, HEARTBEAT, TELEMETRY, COMMAND_DELIVERY, COMMAND_ACK, COMMAND_RESULT, UPDATE_ANNOUNCE, UPDATE_STATUS, POLICY_UPDATE, ALERT, ERROR.

### Command Envelope
- Includes message_id, trace_id, seq, header (version/timestamp/ttl/priority), body (method/params), meta (device_id/origin_user_id/policy_version), and sig.

### Kernel IOCTL
- IOCTLs carry opcode, parameters, and signature.
- Kernel validates opcode allowlist and signature before execution.

## 6) Storage, Queues, and State
- Control Plane: MySQL (system of record), Redis (queues/caching).
- Gateway: Redis streams for telemetry; device presence tracking.
- Agent: local SQLite queue for offline buffering (documented).
- Mobile: local cache for session and offline data (Flutter).

## 7) Observability and Operations
- Audit logging and compliance checks live in Control Plane.
- Agent and kernel report error conditions via telemetry and alerts.
- Documented failure modes include WSS outages, clock skew, cert expiry, revocation failures, kernel service downtime, and OTA rollback.

## 8) CI/CD and Testing
- CI workflows exist for agent, backend, and mobile builds.
- Tests are present in gateway, agent, kernel guard, control plane, and mobile client.
- Docker-based dev stack and setup scripts exist for local development.

## 9) Known Gaps and Limitations (Documented)
- Payload encryption is not fully enforced (signatures are implemented).
- mTLS is planned for production but not fully enforced everywhere.
- Kernel driver signing is not addressed for production deployment.
- Gateway and workers are still evolving; telemetry pipelines and persistence are in progress.
- UI polish for mobile client is a known medium-priority gap.

## 10) What Quoodle Is
- A multi-component research system for secure remote management of Windows endpoints.
- A reference implementation emphasizing cryptographic verification and trust separation.
- A simulated EMM/EDR stack with mobile UI, control plane, gateway, agent, and kernel executor.
- A monorepo with infrastructure and CI/CD scaffolding for local and staged deployments.

## 11) What Quoodle Is Not
- Not a production-ready enterprise EDR/MDM platform.
- Not multi-tenant SaaS (single-tenant architecture is documented).
- Not a general-purpose endpoint agent for macOS or Linux.
- Not a fully hardware-backed key storage system (TPM/HSM is simulated).
- Not an end-to-end encrypted control channel in its current form.
- Not a direct device executor from the Control Plane (execution always happens on agent/kernel).
- Not a system that can safely operate without the Control Plane keys and policy authority.

## 12) Practical Summary
Quoodle is a security-focused, modular device control system intended for research and educational use. It prioritizes strong integrity guarantees and separation of responsibilities over broad platform coverage or production hardening. It is comprehensive in architectural scope, but still contains documented gaps in encryption enforcement, kernel signing, and production-grade operations.
