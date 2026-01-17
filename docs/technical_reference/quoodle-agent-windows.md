# 💻 Subsystem: Quoodle Windows Agent

**Component**: `quoodle-agent-windows`
**Type**: Windows Service (C++ / user-mode)

---

## 1. Subsystem Purpose

### What it does
*   **Persistent Presence**: Runs as a background service (SYSTEM).
*   **Command Valve**: Receives commands, verifies signatures, and passes them to Kernel.
*   **Telemetry Producer**: Scrapes OS metrics and sends to Gateway.

### What it explicitly does NOT do
*   It does **not** execute privileged ops directly (reboot, lock, etc. are delegated to Kernel).
*   It does **not** update itself without Kernel assistance (staging area).

### Why it exists
To act as the "smart" network-facing component. We do not want the networking stack (TLS, JSON parsing) inside the Kernel for stability and security reasons.

---

## 2. Trust Model

### What it trusts
*   **Gateway**: For transport only.
*   **Control Plane**: For command authority (verification of Ed25519 signatures).
*   **Kernel**: Trusts the local driver to execute correctly.

### What it does NOT trust
*   **Local User**: Assumes the local admin might be hostile (tamper resistance).
*   **Network Command**: Rejects any command without a valid signature from the Control Plane Key.

---

## 3. Inputs & Outputs

### Inputs
*   **WSS**: Command Envelopes.
*   **OS**: Performance Counters (PDH).
*   **Kernel**: IOCTL Responses.

### Outputs
*   **WSS**: Heartbeats, Results, Telemetry.
*   **IOCTL**: Structured requests to Kernel.

---

## 4. Internal Logic (High-Level)

### Core Responsibilities
1.  **Boot**: Load config, load keys (DPAPI).
2.  **Connect**: Establish WSS to Gateway.
3.  **Loop**:
    *   Send Heartbeat (every 30s).
    *   Read WSS Message.
    *   If Command: Verify Sig -> Dispatch to IOCTL Queue.
    *   If IOCTL Result: Sign -> Send back to WSS.

### Error Handling
*   **WSS Disconnect**: Exponential backoff retry (1s, 2s, 4s... 60s).
*   **Banned**: If receiving 403 Forbidden, stop retrying for 5m.

---

## 5. Current State (Assessment)

### Working Features
*   [x] Basic Service Skeleton.
*   [x] Boost.Asio WSS setup.

### Broken / Missing Features
*   [ ] **Signature Verification**: "No controller signature verification" (Critical Gap #4).
*   [ ] **IOCTL Schema**: Incomplete request structure (Gap #5).
*   [ ] **Reconnection**: No backoff logic implemented (Gap #6).
*   [ ] **Queue**: Uses in-memory queue; commands lost on restart (Gap #11).

### Known Bugs
*   Leaks memory if WSS connection flaps rapidly.

---

## 6. Open Dependencies / Blockers

*   **Waiting on**: `quoodle-kernel-guard` to expose all 14 opcodes. Currently only 2 are wired.

---

## 7. Risks & Failure Modes

*   **Spoofing**: Until signature verification is fixed, anyone on the network can command the agent.
*   **Service Kill**: Admin users can `sc stop` the service unless the Kernel Guard prevents it (Tamper Check).
