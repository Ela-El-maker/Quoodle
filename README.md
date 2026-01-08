# 📘 **Secure Device Control System — Ferov**

### *Full Architecture • Trust Model • Repository Structure • Runtime Flows • Development Roadmap*

---

## 🧭 **1. Overview**

The **Secure Device Control System** is a multi-service, cryptographically secure platform that enables a mobile user to remotely monitor, manage, and control a Windows device.
The system is built for **research, academic simulation, and security demonstrations**, reflecting real-world enterprise architectures (MDM/EDR-like).

**Core Components**

| Component                  | Role                                                                           |
| -------------------------- | ------------------------------------------------------------------------------ |
| **Mobile App (Flutter)**   | User interaction, pairing, telemetry view, commands, alerts                    |
| **Laravel Backend**        | Identity, CA, JWT auth, policy engine, command ingestion, audit                |
| **FastAPI Controller**     | Real-time WSS gateway, telemetry pipeline, command dispatch, OTA orchestration |
| **Windows Agent (C++)**    | Device connector, telemetry producer, command executor (user-mode)             |
| **Kernel Service (C/C++)** | Privileged operations (IOCTL), updates, attestation, tamper checks             |
| **Infrastructure**         | Docker, Kubernetes, CI/CD, Terraform                                           |
| **Specs & Docs**           | JSON architecture definitions, protocols, flows                                |

The system enforces **strong cryptographic identity**, **strict command validation**, **auditable actions**, **OTA update reliability**, and **multi-layer policy enforcement**.

---

## 🔐 **2. Security Principles**

The architecture is designed around:

* **Strict trust boundaries**
* **End-to-end canonical JSON + Ed25519 signatures**
* **JWT-based identity with KID rotation**
* **Device certificates issued by intermediate CA**
* **Secure IOCTL requests to KernelService**
* **Short-lived, tamper-evident audit logs**
* **Policy evaluation at 3 layers**: Laravel → FastAPI → Agent

Security is treated as **a first-class subsystem**, not an afterthought.

---

## 🏗️ **3. System Architecture Overview**

```
+-------------------+        +--------------------+        +------------------------+
|    Mobile App     | <----> |      Laravel       | <----> |        FastAPI         |
|   (Flutter UI)    |        |  Auth, CA, Policy  |        |   WSS Real-time Hub    |
+-------------------+        +--------------------+        +------------------------+
                                                              |
                                                              |
                                                  +-----------------------+
                                                  |    Windows Agent      |
                                                  |      (C++ User Mode)  |
                                                  +-----------------------+
                                                              |
                                                              |
                                                  +-----------------------+
                                                  |    Kernel Service     |
                                                  |      (C / C++ )       |
                                                  +-----------------------+
```

---

## 📂 **4. Monorepo Structure**

```
secure-device-control/
│
├── backend-laravel/
├── backend-fastapi/
├── windows-agent/
├── kernel-service/
├── mobile-app/
├── infrastructure/
├── docs/
│
├── .github/
├── .editorconfig
├── .gitignore
└── README.md   ← (this file)
```

Each repository is fully described in `docs/architecture/` and has its own README.

---

## 📚 **5. Documentation Index**

All JSON specs that define the system live in:

```
docs/specs/
│
├── FastAPI ↔ Laravel (REST + Webhook Control Channel).json
├── Full System Json.json
├── Laravel ↔ Mobile App (REST + notifications).json
├── MasterBlueprint-v3.json
├── Missing System Components.json
├── System flow.json
├── WindowsAgent ↔ FastAPI (WSS control channel).json
└── WindowsAgent ↔ KernelService Interface.json
```

Documentation areas:

```
docs/
│
├── specs/              # Canonical JSON specifications
├── architecture/       # Big-picture and sequence diagrams
├── protocols/          # WSS, IOCTL, REST API documentation
├── onboarding/         # Developer setup & contributions
├── security/           # Threat model, audit chain, compliance
└── report/             # Academic write-up (optional)
```

---

## 🔄 **6. Full System Runtime Flow**

Below is the authoritative high-level summary across all JSON specs.

### **6.1 Discovery (Unauthenticated)**

1. Windows Agent boots → opens WSS with minimal hashed identifiers
2. FastAPI verifies structure → issues `challenge_token`
3. Agent proves possession of keys → FastAPI notifies Laravel
4. Laravel displays device as **Pending Pairing**

---

### **6.2 Pairing (Mobile ↔ Laravel ↔ Agent)**

1. Mobile user registers (public key uploaded)
2. Agent requests pairing → shows QR containing `pair_token`
3. Mobile scans QR → Laravel validates token
4. Laravel issues device certificate from Intermediate CA
5. Agent reconnects to FastAPI using certificate → becomes **trusted device**

---

### **6.3 Authentication & Presence**

* Agent sends `AUTH` message signed with device cert
* FastAPI validates → assigns `session_id`
* Agent starts:

  * Heartbeat
  * Telemetry streaming
  * Policy synchronization

Presence is tracked via Redis TTL.

---

### **6.4 Command Lifecycle (Full Round Trip)**

```
Mobile → Laravel → Redis → FastAPI → Agent → KernelService → Agent → FastAPI → Laravel → Mobile
```

Sequence:

1. Mobile sends command
2. Laravel:

   * Validates user
   * Evaluates policy
   * Signs command
   * Enqueues to Redis
3. FastAPI:

   * Verifies signature
   * Checks device presence
   * Sends COMMAND_DELIVERY via WSS
4. Agent:

   * Validates signature, policy, TTL
   * ACKs command
   * Calls KernelService via IOCTL
5. KernelService executes opcode and returns signed result
6. Agent returns `COMMAND_RESULT` to FastAPI
7. FastAPI → Laravel → Mobile notifications
8. Audit logs written end-to-end

---

### **6.5 Telemetry Flow**

* Agent sends periodic metrics: CPU, RAM, DISK, NET, risk indicators
* FastAPI ingests → Redis streams → Analytics workers → MySQL
* Alerts forwarded to:

  * Mobile
  * Agent
  * Admin dashboard

---

### **6.6 OTA Update Flow**

1. Admin creates release in Laravel
2. FastAPI announces update
3. Agent performs:

   * Precheck
   * Download
   * Verify manifest signature
   * `STAGE_UPDATE` → KernelService
   * `COMMIT_UPDATE` + optional reboot
4. Post-install report flows upward to dashboard

---

### **6.7 Policy & Compliance**

Policies enforced at 3 layers:

* **Laravel (primary, authoritative)**
* **FastAPI (secondary routing checks)**
* **Agent (local last-line enforcement)**

Compliance engine periodically verifies:

* Agent version
* OS build
* Certificate validity
* Policy hash correctness
* Tamper checks

Alerts generated if any violation occurs.

---

## 🧱 **7. Repository Summaries**

### **7.1 backend-laravel**

Handles:

* JWT & JWKS
* User auth
* Certificate Authority operations
* Device pairing APIs
* Policy engine
* Command ingestion (signed envelopes)
* OTA release management
* Audit chain
* Dashboard logic

### **7.2 backend-fastapi**

Provides:

* WebSocket controller
* Device real-time routing
* Telemetry ingestion
* Command dispatcher
* OTA distribution backend
* Presence tracker
* Queue workers (DLQ, analytics, alerts)

### **7.3 windows-agent (C++)**

Implements:

* WSS client (TLS 1.3)
* Command queue
* Signature verification
* Policy caching
* Telemetry collector
* IOCTL interface to KernelService

### **7.4 kernel-service (C/C++)**

Privileged executor for:

* System control (lock, reboot, shutdown)
* Process enumeration
* Attestation & tamper checks
* Update staging and commit
* Strict signature/param validation

### **7.5 mobile-app (Flutter)**

User UI for:

* Registration
* Device pairing
* Command interface
* Live telemetry
* Alerts/logs
* Updates & compliance status

### **7.6 infrastructure**

Contains:

* Docker images
* Kubernetes manifests
* Terraform modules
* GitHub Actions CI/CD
* Monitoring stack (Prometheus + Grafana)

### **7.7 docs**

Single source of truth for:

* Specs
* Sequence diagrams
* Protocol definitions
* Threat modeling
* Onboarding & training materials

---

## 🧪 **8. Testing Strategy**

### **Unit tests**

* Laravel: Services, Auth, PolicyEvaluator, CA
* FastAPI: WSS handlers, signature validation, queue workers
* Agent: signature logic, queue logic, IOCTL parser
* KernelService: opcode validation, attestation logic

### **Integration tests**

* Full command round trip
* OTA update simulation
* Pairing sequence
* Policy update + enforcement
* Failure cases (device offline, invalid signature, expired TTL)

### **End-to-End tests**

* Local environment via Docker Compose
* Synthetic devices + mock KernelService
* Chaos testing (network dropout, backpressure, failures)

---

## 🧭 **9. Development Roadmap Overview**

Your development flow is broken into phases:

1. **Phase 0** – Repo setup, skeleton generation, CI
2. **Phase 1** – Laravel auth + CA
3. **Phase 2** – FastAPI WSS AUTH
4. **Phase 3** – Agent WSS client + AUTH protocol
5. **Phase 4** – Telemetry + heartbeat
6. **Phase 5** – Command lifecycle
7. **Phase 6** – KernelService IOCTL basics
8. **Phase 7** – Full round-trip command execution
9. **Phase 8** – Mobile app skeleton
10. **Phase 9** – OTA update pipeline
11. **Phase 10** – Policy, compliance, audit hardening
12. **Phase 11** – Deployment, monitoring, TLS/mTLS
13. **Phase 12** – Nonfunctional: scaling, resilience, test harnesses

A detailed version exists in `Development Flow.md`.

---

## 🎓 **10. Project Status**

This repository contains:

* Complete architecture documentation
* Complete JSON specifications
* Complete development plan
* Production-grade folder skeleton for every repo

**Next step:** begin Phase 0 — scaffold the monorepo, create folders, and initialize each repo.

---

## ❤️ **11. Contribution**

This is an academic simulation and open for improvement.
Please follow:

* `docs/onboarding/contribution_guide.md`
* Format all code with Prettier, PHP-CS-Fixer, Black, or clang-format depending on repo
* Sign-off commits if contributing to core protocols

# ferov
