# 🎮 Subsystem: Quoodle Control Plane

**Component**: `quoodle-control-plane`
**Type**: Laravel Application (PHP / MySQL / Redis)

---

## 1. Subsystem Purpose

### What it does
*   **Root of Trust**: Manages the Certificate Authority (CA) and signs all Device Certificates.
*   **Identity Provider**: Authenticates Users and Agents; issues JWTs.
*   **Policy Engine**: Evaluates rules (e.g., "User X can reboot Device Y at Time Z").
*   **Command Authority**: Signs command envelopes before dispatching to Gateway.

### What it explicitly does NOT do
*   It does **not** maintain open connections to devices (Gateway does that).
*   It does **not** execute commands.

### Why it exists
To centralize trust and policy. By decoupling policy (Laravel) from transport (Gateway), we ensure that a compromise of the edge/transport layer does not grant ability to sign new commands or mint new identities.

---

## 2. Trust Model

### What it trusts
*   **Database**: Implicit trust in MySQL data integrity.
*   **Gateway**: Trusts webhook updates regarding device presence/status (verified via signature).

### What it does NOT trust
*   **Mobile Client**: Treat as untrusted input; rigorous validation of all params.
*   **Agents**: Treat as potentially compromised; require mTLS and signature on every request.

### Boundaries & Assumptions
*   **Boundary**: Internal Network (Gateway) & Public Internet (Mobile).
*   **Assumption**: The private keys (CA, Signing) stored in storage/_keys are secure (in reality, should be HSM).

---

## 3. Inputs & Outputs

### Inputs
*   **REST API**: JSON from Mobile Client.
*   **Webhooks**: JSON from Gateway (device status, cmd results).
*   **Admin Console**: Operator inputs.

### Outputs
*   **Signed Envelopes**: JSON objects + Ed25519 Signature.
*   **Certificates**: X.509 Device Certs (PEM).
*   **Audit Logs**: Immutable log entries.

---

## 4. Internal Logic (High-Level)

### Core Responsibilities
1.  **Pairing / Enrollment**:
    *   Receive `pair_token`.
    *   Validate token.
    *   Sign CSR from Agent.
    *   Return Certificate.
2.  **Command Dispatch**:
    *   Receive command intent.
    *   Check RBAC/Policy.
    *   Sign payload.
    *   Push to Redis/HTTP for Gateway.

### Decision Points
*   **Policy Check**: If `User.Role != Admin` AND `Command == Wipe`, REJECT.

### Data Handling
*   **Storage**: MySQL (Users, Devices, Policies, Logs). Redis (Job Queue, Caching).
*   **Sensitive Data**:
    *   User Passwords (Bcrypt).
    *   CA Private Key (File/Vault).
    *   Command Signing Key (File/Vault).

---

## 5. Current State (Assessment)

### Working Features
*   [x] Database Schemas (Migrations).
*   [x] Basic User Models.
*   [ ] **JWT Auth**: Middleware is missing (Critical Gap #3).

### Broken / Missing Features
*   [ ] **API Protection**: Routes are currently open/unprotected.
*   [ ] **OTA Release Flow**: Stubs only.
*   [ ] **Rate Limiting**: Not implemented.

### Known Technical Debt
*   CA logic currently uses OpenSSL shell execs or raw PHP libraries instead of a proper PKI service.

---

## 6. Open Dependencies / Blockers

*   **Waiting on**: `quoodle-gateway` to define the exact webhook payload structure for command results.

---

## 7. Risks & Failure Modes

*   **Key Compromise**: If the server filesystem is breached, the CA key is stolen -> Total System Collapse.
*   **Database Lock**: Heavy audit logging might lock tables, blocking command issuance.
