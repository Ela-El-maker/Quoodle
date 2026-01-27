# 🧭 Quoodle Project Overview

**Document Status**: Synchronized with codebase (Jan 2026)
**Version**: 1.1

## 1. High-Level Architecture & Purpose

Quoodle is a **Secure Device Control System** for research and production-grade simulation of high-assurance EMM/EDR platforms. It enables cryptographically signed, auditable remote management of Windows and Linux endpoints, with all flows validated end-to-end.

### Business Goals

- **Demonstrate High Assurance**: Prove that remote control of endpoints can be done with strict cryptographic verification at every hop.
- **Research & Education**: Serve as a reference implementation for "Zero Trust" device management patterns.
- **Modular Design**: Decoupled components allow independent scaling and development.
- **Production Validation**: All core flows (register, pair, command, telemetry, audit) are E2E tested and validated.

### Technical Goals

- **End-to-End Integrity**: Every command is signed by the authority (Control Plane) and verified by the executor (Agent/Kernel).
- **Privileged Isolation**: Sensitive operations are restricted to a kernel driver or privileged daemon, unreachable by user-mode malware.
- **Real-Time Responsiveness**: WebSocket-based command delivery < 500ms latency.
- **Audit-by-Default**: All actions are logged with immutable, append-only audit trails.
- **Replay/TTL Enforcement**: All flows enforce monotonic sequence, TTL, and anti-replay.

## 2. Global Constraints & Out-of-Scope

- **Platform Support**:
  - **Target**: Windows 10/11 (x64), Linux endpoints (C++ agent/daemon).
  - **Mobile**: Android/iOS via Flutter.
  - **Backend**: Linux-based containers (Docker Compose, K8s).
- **Scalability Limits**:
  - Design targets ~10k connected agents per Gateway instance.
  - Redis used as ephemeral bus; MySQL as persistent source of truth.
- **Out of Scope**:
  - MacOS agent (future work).
  - Multi-tenant SaaS architecture (currently single-tenant).
  - Hardware-backed key storage (TPM) is currently simulated in software.

## 3. Critical Paths

1.  **Pairing Path**: `Mobile -> Control Plane -> Gateway -> Agent`. QR code and agent key binding required for onboarding.
2.  **Command Path**: `Mobile -> Control Plane -> Gateway -> Agent -> Kernel/Privileged Daemon`. Signed command envelope, verified at each hop.
3.  **Telemetry Path**: `Agent -> Gateway -> Redis -> Workers -> MySQL`. Telemetry is streamed, validated, and persisted for compliance and analytics.
4.  **Audit Path**: All actions (commands, results, pairing, compliance) are logged and queryable for audit.
