# 📘 **Secure Device Control System**

*(Academic Simulation — Full Architecture & Protocol Specification)*

---

# **1. Overview**

The **Secure Device Control System** is a fully auditable, cryptographically enforced platform enabling a user’s **mobile app** to securely control and monitor their **Windows device** through a layered backend architecture consisting of:

* **Laravel** — Identity, policy engine, CA, command orchestration, and APIs
* **FastAPI** — Real-time WSS controller, device router, telemetry gateway
* **WindowsAgent** — System-level device agent with kernel operations
* **KernelService** — Privileged executor of sensitive/critical system commands
* **Mobile App (Flutter)** — User interface for device control, pairing, alerts, logs

This project provides an academically complete simulation of an enterprise-grade device management system, implementing strong cryptographic identity, multi-layer verification, real-time telemetry, secure command execution, and full auditability.

**Scope:**
All operations simulated; secure for academic demonstration environments.
*(Spec reference: Full System Json.json, MasterBlueprint-v3.json)*

---

# **2. High-Level Architecture**

```
+--------------+       +------------------+       +--------------------+
|  Mobile App  | <---> |      Laravel      | <---> |      FastAPI       |
+--------------+       |  Auth, Policy,    |       |   Device Router    |
                       |  CA, Commands     |       |   WSS Controller   |
                       +------------------+       +--------------------+
                                                          |
                                                          |
                                              +-----------------------+
                                              |    Windows Agent      |
                                              |    (User Mode)        |
                                              +-----------------------+
                                                          |
                                                          |
                                              +-----------------------+
                                              |    KernelService      |
                                              |   (Privileged Ops)    |
                                              +-----------------------+
```

*(Spec reference: System flow.json, MasterBlueprint-v3.json)*

---

# **3. Core System Components**

## **3.1 Windows Agent**

A user-mode service responsible for:

* Opening WSS connections to FastAPI
* Receiving, validating, and acknowledging commands
* Executing safe commands locally
* Passing privileged ops to KernelService via IOCTL
* Streaming telemetry and heartbeat signals

*(Spec reference: WindowsAgent ↔ FastAPI (WSS control channel).json)*
*(Spec reference: AgentKernelInterface.json)*

---

## **3.2 KernelService (Privileged Executor)**

A controlled, minimal interface exposing a narrow set of safe enumerated system operations, such as:

* Lock screen
* Reboot / Shutdown
* Attestation & tamper checks
* Update staging and commit

All requests must:

* Use canonical JSON
* Include an Ed25519 signature
* Use a strictly increasing sequence counter
* Match one of the **AllowedOpcodes**

*(Spec reference: WindowsAgent ↔ KernelService Interface.json; AgentKernelInterface.json)*

---

## **3.3 FastAPI Controller**

Acts as the real-time gateway for:

* Routing commands to online devices
* Receiving execution results
* Telemetry ingestion
* Presence tracking (agent online/offline)
* Alert broadcasting

FastAPI's WSS protocol includes:

* AUTH / AUTH_ACK
* TELEMETRY
* COMMAND_DELIVERY
* COMMAND_ACK
* COMMAND_RESULT
* UPDATE_ANNOUNCE
* POLICY_UPDATE

*(Spec reference: FastAPI ↔ Laravel (REST + Webhook Control Channel).json)*
*(Spec reference: AgentFastAPIInterface.json)*

---

## **3.4 Laravel Backend**

Provides:

* User & device identity
* JWT issuance
* CA certificate authority for device certs
* Command ingest & validation
* Policy enforcement
* OTA update distribution
* Mobile APIs (REST + WSS notifications)

*(Spec reference: Laravel ↔ Mobile App (REST + notifications).json)*

---

---

# **4. End-to-End Runtime Flows**

Below is a compact summary of all flows defined across your JSON specification files.

---

# **4.1 Discovery Flow (Unauthenticated)**

Unpaired Windows Agents broadcast their existence securely without leaking identifiers.

**Key points**

* Sends only **hwid_hash**, **nonce**, **agent manifest hash**
* FastAPI sends back short-lived **challenge_token**
* Agent completes challenge → Laravel notified
* Device enters **Pending Pairing** list

*(Spec reference: System flow.json — DiscoveryFlow)*

---

# **4.2 Pairing Flow (Mobile ↔ Laravel ↔ Agent)**

Secure association of a device with a user.

**Stages**

1. User registers on Mobile App → Laravel
2. Agent requests pairing token from Laravel
3. Agent displays QR code containing `pair_token`
4. Mobile scans → Laravel links user ↔ device
5. Laravel issues **device certificate**
6. Agent authenticates with FastAPI over WSS using cert

Security:

* All JWTs signed by Laravel
* Device certs signed by CA intermediary
* HWID collisions cause explicit 409 conflict

*(Spec reference: System flow.json — PairingFlow)*

---

# **4.3 Secure Command Execution Flow**

The heart of the system — command lifecycle with full audit, reliability, and cryptographic enforcement.

**Pipeline**

Mobile → Laravel → Redis → FastAPI → WindowsAgent → KernelService → WindowsAgent → FastAPI → Laravel → Mobile

**Lifecycle states**

```
queued → sent → ack_received → executing → result_posted → completed / failed
```

**Highlights**

* Canonical JSON envelopes with Ed25519 signatures
* TTL enforcement (no stale commands)
* Sequence validation (anti-replay)
* On-device queueing for reliability
* Large artifacts uploaded via presigned URLs
* Automatic retries + DLQ support

*(Spec reference: Full System Json.json — CommandExecutionFlow)*

---

# **4.4 Telemetry Flow**

Real-time telemetry streaming from WindowsAgent → FastAPI → Redis → Analytics → Dashboard.

Metrics include:

* CPU / RAM / Disk
* Network usage
* Risk score analysis
* Heartbeat for presence tracking

Alerts automatically propagated when anomalies detected.

*(Spec reference: Full System Json.json — TelemetryFlow)*

---

# **4.5 OTA Update Flow**

OTA updates are announced by Laravel and delivered via FastAPI.

Includes:

* Manifest validation
* Signature verification
* Staging → Commit / Rollback
* Progress reporting

*(Spec reference: FastAPI_Laravel_Interface.json — Update Deploy + Update Status)*
*(Spec reference: AgentKernelInterface.json — Update opcodes)*

---

# **4.6 Key Management Flow (Cryptographic Trust Lifecycle)**

Enterprise-grade identity lifecycle:

* Root & Intermediate CA (HSM-backed)
* Device cert issuance
* JWT signing key rotation
* Revocation (CRL/OCSP + push)
* Emergency mass-revoke scenarios
* TPM-bound private keys on device

*(Spec reference: Full System Json.json — KeyManagementFlow)*

---

# **5. Protocol Specifications**

The following summaries reference the detailed JSON schemas found in your uploaded files.

---

## **5.1 KernelService IOCTL Protocol**

### **Request Schema**

* `request_id`
* `opcode` (must match enumerated set)
* `params`
* `agent_sequence`
* `policy_hash`
* `signature`

### **Response Schema**

* `request_id`
* `status` (`ok`, `failed`, `denied`, etc.)
* `error_code`
* `result`
* `signature`

**Allowed Opcodes:**
Lock screen, reboot, shutdown, logout, process list, attestation, update commands.

*(Spec reference: AgentKernelInterface.json)*

---

## **5.2 Agent ↔ FastAPI WebSocket Protocol**

**Message Types**:

| Direction          | Type                                                                   |
| ------------------ | ---------------------------------------------------------------------- |
| Agent → Controller | AUTH, HEARTBEAT, TELEMETRY, COMMAND_ACK, COMMAND_RESULT, UPDATE_STATUS |
| Controller → Agent | AUTH_ACK, COMMAND_DELIVERY, UPDATE_ANNOUNCE, POLICY_UPDATE, ALERT      |

**All messages share a common envelope:**

* `message_id`
* `timestamp`
* `type`
* `device_id`
* `session_id`
* `sig`

*(Spec reference: AgentFastAPIInterface.json)*

---

## **5.3 FastAPI ↔ Laravel REST/Webhook Interface**

### **Laravel → FastAPI**

* `/command/dispatch`
* `/policy/push`
* `/update/deploy`

### **FastAPI → Laravel**

* `/device/online`
* `/device/offline`
* `/command/result`
* `/telemetry/summary`
* `/security/attestation`

All requests cryptographically signed (Ed25519).

*(Spec reference: FastAPI ↔ Laravel (REST + Webhook Control Channel).json)*

---

## **5.4 Mobile App ↔ Laravel REST + Notifications**

Features:

* Registration, login, JWT refresh
* Device list & detail view
* Telemetry history
* Command execution
* Alerts and audit logs
* Pairing via QR tokens

*(Spec reference: Laravel ↔ Mobile App (REST + notifications).json)*

---

# **6. Security Architecture**

Security model spans five layers:

### **1. Authentication**

* Mobile user → JWT + optional 2FA
* WindowsAgent → mTLS device certificate + JWT
  *(Spec references: Laravel auth routes; AgentFastAPI AUTH handshake)*

### **2. Authorization**

* Policy Engine uses:

  * user role
  * device state
  * risk level
  * command risk class

*(Spec reference: Missing System Components.json — PolicyEngine_API)*

### **3. Integrity**

* Every command, every WSS message, and every IOCTL request is **signed**
* Canonical JSON removes whitespace + alphabetically sorted keys
* Hardware-backed key storage recommended

### **4. Confidentiality**

* WSS (TLS 1.3)
* Optional AES-GCM encryption of command payloads
* Encrypted artifact uploads

### **5. Auditability**

* Immutable hash-linked audit trail
* Evidence stored in S3 with replication
* Each command and result mapped by trace_id

*(Spec references: AuditTrail_API, CommandExecutionFlow)*

---

# **7. Reliability & Observability**

### **Reliability**

* Dead-letter queues (DLQ)
* Retry policies (send + execution)
* On-device queue prevents loss during restart
* Backpressure detection for overload

### **Observability**

* Structured JSON logs
* Metrics for ingestion, dispatch latency, execution time
* Tracing via `trace_id` propagation

*(Spec references: Full System Json.json — Observability)*

---

# **8. Developer Notes**

### **Project Goals**

* Demonstrate secure multi-layer communication
* Show end-to-end attestation and command execution
* Provide auditable flows for research
* Blueprint for enterprise security architectures

### **What is NOT included**

* Production cryptographic key storage
* Real kernel-mode drivers (KernelService is simulated)
* Real hardware telemetry or tamper protection

---

# **9. File Specification References (Full List)**

The following files were used to generate this README:

* **MasterBlueprint-v3.json** 
* **Missing System Components.json** 
* **Laravel ↔ Mobile App (REST + notifications).json** 
* **FastAPI ↔ Laravel (REST + Webhook Control Channel).json** 
* **WindowsAgent ↔ FastAPI (WSS control channel).json** 
* **WindowsAgent ↔ KernelService Interface.json** 
* **System flow.json** 
* **Full System Json.json** 

---
