# 🧭 Quoodle Project Overview

**Document Status**: Draft
**Version**: 1.0

## 1. High-Level Architecture & Purpose

Quoodle is a **Secure Device Control System** designed to simulate a high-security Enterprise Mobility Management (EMM) or Endpoint Detection and Response (EDR) platform.

### Business Goals
*   **Demonstrate High Assurance**: Prove that remote control of Windows devices can be done with strict cryptographic verification at every hop.
*   **Research & Education**: Serve as a reference implementation for "Zero Trust" device management patterns.
*   **Modular Design**: decoupled components allowing independent scaling and development.

### Technical Goals
*   **End-to-End Integrity**: Every command is signed by the authority (Control Plane) and verified by the executor (Agent/Kernel).
*   **Privileged Isolation**: Sensitive operations are restricted to a kernel driver, unreachable by user-mode malware.
*   **Real-Time Responsiveness**: WebSocket-based command delivery < 500ms latency.

## 2. Global Constraints & Out-of-Scope

*   **Platform Support**:
    *   **Target**: Windows 10/11 (x64) only.
    *   **Mobile**: Android/iOS via Flutter.
    *   **Backend**: Linux-based containers.
*   **Scalability Limits**:
    *   Current design targets ~10k connected agents per Gateway instance.
    *   Redis used as ephemeral bus; MySQL as persistent source of truth.
*   **Out of Scope**:
    *   MacOS / Linux Agents.
    *   Multi-tenant SaaS architecture (currently single-tenant).
    *   Hardware-backed key storage (TPM) is currently simulated in software.

## 3. Critical Paths

1.  **Pairing Path**: `Mobile -> Control Plane -> Gateway -> Agent`. Failure here prevents new device onboarding.
2.  **Command Path**: `Mobile -> Control Plane -> Gateway -> Agent -> Kernel`. Failure here renders the system useless for control.
3.  **Telemetry Path**: `Agent -> Gateway -> Redis -> Workers -> MySQL`. Failure here causes blindness but not loss of control.
