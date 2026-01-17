# 🔐 Quoodle Trust Model

**Version**: 1.0
**Status**: Active

This document defines the cryptographic trust boundaries and enforcing authorities within the Quoodle system.

---

## 1. Root of Trust

The **Control Plane (`quoodle-control-plane`)** acts as the ultimate Root of Trust for the entire system.

- **Certificate Authority (CA)**: The Control Plane manages the CA private key used to sign all Device Certificates.
- **Identity Provider (IdP)**: The Control Plane issues all user and agent JWTs.
- **Policy Authority**: The Control Plane signs all policy bundles and command envelopes.

> 🔴 **Critical**: Compromise of the Control Plane keys allows an attacker to impersonate any user, spoof commands, and take control of all agents.

---

## 2. Trust Boundaries

### 2.1 Mobile ↔ Control Plane
- **Trust**: `quoodle-mobile-client` trusts `quoodle-control-plane` via standard **TLS (HTTPS)**.
- **Auth**: Control Plane validates User via **JWT** (signed by Control Plane).
- **Intent**: Mobile client signs command requests with a transient user key (future roadmap).

### 2.2 Agent ↔ Gateway
- **Trust**: `quoodle-agent-windows` trusts `quoodle-gateway` via **TLS (WSS)** and **Ed25519 Signatures**.
    - The Agent verifies the `server_signature` on every `COMMAND_DELIVERY`.
- **Auth**: Gateway validates Agent via **mTLS** (Device Certificate signed by CA).

### 2.3 Agent ↔ Kernel
- **Trust**: `quoodle-kernel-guard` trusts `quoodle-agent-windows` **conditionally**.
    - The Kernel verifies the **Ed25519 signature** on every IOCTL request.
    - The Kernel enforces an **Allowlist** of opcodes.
    - The Kernel validates the `agent_sequence` to prevent replay attacks.

---

## 3. Key Management

| Key | Type | Owner | Storage | Rotation |
| :--- | :--- | :--- | :--- | :--- |
| **CA Root Key** | Ed25519 Priv | Control Plane | AWS KMS / HSM | Yearly |
| **Command Signing Key** | Ed25519 Priv | Control Plane | Vault / Secure Env | Quarterly |
| **Device Key** | Ed25519 Priv | Agent | Windows DPAPI | On Re-pairing |
| **Kernel Verification Key** | Ed25519 Pub | Kernel | Compile-time / Driver Signing | Driver Update |

---

## 4. Threat Model Mitigation

| Threat | Mitigation |
| :--- | :--- |
| **Agent Compromise** | Kernel driver validates signatures; tamper checks detect hollowing. |
| **Gateway Compromise** | Gateway cannot sign commands; Agent rejects unsigned envelopes. |
| **Network Man-in-the-Middle** | mTLS forces mutual auth; TLS 1.3 encrypts traffic. |
| **Replay Attack** | All messages include monotonic sequence + timestamp + nonces. |
