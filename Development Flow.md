# 🚀 **Development Flow.md**

### *Full Engineering Roadmap for the Secure Device Control System (Aligned With README v2)*

---

# 🧭 **0. Purpose of This Document**

This document defines **exactly how to build the system from scratch**, one phase at a time, in the correct order, with the correct boundaries, ensuring:

* No subsystem is built prematurely
* All cryptographic trust flows are enforced
* Cross-service interfaces remain consistent
* Minimal working skeletons are validated before adding complexity
* Every subsystem can be tested independently and end-to-end

This roadmap is the **master engineering plan** for the Secure Device Control System.

---

# 🏗️ **1. Project Setup (Phase 0)**

### *Goal: Initialize repositories, skeletons, CI, and documentation.*

---

## **1.1 Create the monorepo**

```
secure-device-control/
│
├── backend-laravel/
├── backend-fastapi/
├── windows-agent/
├── kernel-service/
├── mobile-app/
├── infrastructure/
└── docs/
```

Use the skeleton structure from `skeleton for all repositories.md`.

---

## **1.2 Initialize each repository**

* Laravel: `laravel new backend-laravel`
* FastAPI: create `pyproject.toml`, `app/main.py`, dependencies etc.
* WindowsAgent: initialize CMake project
* KernelService: C/C++ project with CMake
* Mobile app: `flutter create mobile-app`
* Infrastructure: create Dockerfiles + k8s templates

---

## **1.3 Set up global GitHub Actions (CI)**

Enable CI workflows for:

* Laravel tests
* FastAPI tests
* Agent build (CMake)
* KernelService build
* Flutter build
* Linting
* Security scans (optional)

---

## **1.4 Populate docs folder**

Copy all JSON specs into:

```
docs/specs/
```

Create placeholders:

* `docs/architecture/overview.md`
* `docs/protocols/ws_protocol.md`
* `docs/security/threat_model.md`
* etc.

---

# 🔐 **2. Identity & Trust Layer (Phase 1)**

### *Goal: Establish cryptographic foundation before any real communication.*

---

## **2.1 Laravel – CA system**

Implement:

* Root CA (offline)
* Intermediate CA (online)
* Device certificate issuer
* Certificate storage (DB + Redis cache)
* CRL/OCSP endpoints (optional academic simulation)

---

## **2.2 Laravel – JWT authority**

* JWT signing keys
* JWKS endpoint (`/.well-known/jwks.json`)
* Key rotation service (7-day rotation)
* KID-based verification

---

## **2.3 FastAPI – trust bootstrap**

* JWKS fetch + caching
* Token verification utilities
* Device certificate verification
* Request signing verification (Ed25519 / RSA-PSS)

---

## **2.4 Test milestone**

You must reach:

✔ Laravel can create & rotate JWT signing keys
✔ FastAPI can validate JWTs
✔ Laravel can issue a mock device certificate
✔ FastAPI can verify that certificate

Only move forward after this passes.

---

# 🌐 **3. FastAPI Real-Time Layer (Phase 2)**

### *Goal: Build minimal WSS controller for agent login.*

---

## **3.1 Basic WSS endpoint**

Implement WSS server with:

* `AUTH` message
* `AUTH_ACK` response
* Session allocation
* Basic Redis integration

---

## **3.2 Presence subsystem**

Implement:

* Redis TTL-based online tracking
* `/webhook/device/online` → Laravel
* `/webhook/device/offline` → Laravel

---

## **3.3 Minimal protocol skeleton**

Add empty handlers:

* `telemetry_handler.py`
* `command_delivery_handler.py`
* `update_handler.py`
* `alert_handler.py`

---

## **3.4 Test milestone**

✔ Agent can connect with dummy message
✔ FastAPI responds with `AUTH_ACK`
✔ Redis presence keys update correctly

Do **NOT** implement command routing yet.

---

# 🪟 **4. Windows Agent Minimal Build (Phase 3)**

### *Goal: Basic WSS client that authenticates.*

---

## **4.1 Implement Agent skeleton**

* Windows service or console app
* CMake structure
* Updater stub
* Logging

---

## **4.2 Implement WSS client**

Use:

* WinHTTP or Boost.Beast
* TLS 1.3
* Certificate loading (local device cert)

---

## **4.3 AUTH handshake**

Implement:

* Load device certificate
* Build canonical AUTH JSON
* Sign AUTH message
* Validate `AUTH_ACK` fields
* Store session_id

---

## **4.4 Test milestone**

✔ Agent connects
✔ FastAPI authenticates
✔ Ready for telemetry & command pipeline

This is the first major milestone.

---

# 📡 **5. Telemetry & Heartbeat (Phase 4)**

### *Goal: Continuous link between Agent and FastAPI.*

---

## **5.1 Agent sends telemetry**

Implement:

* CPU, RAM, disk, network
* Signed telemetry envelope
* Configurable interval

---

## **5.2 FastAPI telemetry ingestion**

* Validate signature
* Store into Redis streams
* Write to MySQL via worker
* Implement `risk_score` calculation

---

## **5.3 Heartbeat**

* Agent sends `heartbeat`
* FastAPI updates presence
* Detect offline events

---

## **5.4 Test milestone**

✔ Telemetry visible in Laravel dashboard
✔ FastAPI maintains presence
✔ Alerts fire for anomalies (optional)

---

# ⚡ **6. Command Lifecycle (Phase 5)**

### *Goal: End-to-end command dispatch (delivery only).*

---

## **6.1 Laravel command ingest**

Implement:

* `/api/command` POST
* Policy engine integration (basic)
* Command signing
* Save to DB
* Publish to Redis stream

---

## **6.2 FastAPI command router**

Implement:

* Read from Redis
* Signature verification
* TTL / sequence checks
* COMMAND_DELIVERY via WSS

---

## **6.3 Agent command receiver**

Implement:

* Validate FastAPI signature
* Validate TTL & sequence
* ACK commands
* Insert into local queue

---

## **6.4 Test milestone**

✔ Command appears on Agent
✔ Agent ACKs
✔ State updates in Laravel (`queued → sent → ack_received`)

NOT executing commands yet.

---

# 🔧 **7. KernelService Integration (Phase 6)**

### *Goal: Implement IOCTL-based privileged operations.*

---

## **7.1 KernelService skeleton**

* C/C++ service with CMake
* IOCTL interface defined using JSON spec
* AllowedOpcodes enum
* RequestSchema / ResponseSchema implemented

---

## **7.2 Basic opcodes**

Implement:

* `EXEC_PING_KERNEL`
* `EXEC_LOCK_SCREEN`
* `EXEC_GET_PROCESS_LIST`

---

## **7.3 Agent → KernelService bridge**

* IOCTL client
* Canonical request builder
* Signature generation
* Response signature validation

---

## **7.4 Test milestone**

✔ Agent can send opcodes
✔ KernelService executes
✔ Agent receives correct responses

---

# 🔁 **8. Full Command Round Trip (Phase 7)**

### *Goal: Entire pipeline works: Mobile → Device → Mobile.*

---

## **8.1 Implement COMMAND_RESULT**

FastAPI:

* Validate agent signature
* Call Laravel `/command/result` webhook

Laravel:

* Update DB state
* Push notification to Mobile
* Append audit entry

Mobile:

* Display command result

---

## **8.2 Large artifacts**

Implement:

* Screenshot/log upload
* Laravel presigned URL issuing
* FastAPI artifact forwarding
* Agent encryption & upload

---

## **8.3 Test milestone**

✔ Full round-trip command works
✔ Artifacts upload correctly
✔ Audit chain logs all operations

This unlocks OTA.

---

# 📦 **9. OTA Update System (Phase 8)**

### *Goal: Reliable update staging & commit.*

---

## **9.1 Laravel release management**

* Create release
* Upload artifacts
* Sign manifest

---

## **9.2 FastAPI OTA coordinator**

* Broadcast `update_available`
* Track device rollout states

---

## **9.3 Agent OTA handler**

* Precheck
* Download
* Verify signature
* Call KernelService: `STAGE_UPDATE`
* Call KernelService: `COMMIT_UPDATE`
* Optional reboot

---

## **9.4 KernelService update ops**

Implement:

* Sandbox staging
* Atomic commit
* Rollback
* Post-install metrics

---

## **9.5 Test milestone**

✔ Update deploys to sample device
✔ Rolls back on failure
✔ Dashboard shows update status

---

# 🛡️ **10. Policy, Compliance & Security Hardening (Phase 9)**

---

## **10.1 Expand PolicyEngine**

Add rules:

* Time windows
* Command rate limiting
* Device posture
* Ethical restrictions
* Multi-approval flows

---

## **10.2 Agent local policy bundle**

* Policy signature validation
* Local enforcement if backend unavailable

---

## **10.3 Compliance Engine**

* Check agent version, OS version
* Certificate expiry
* Tamper check
* Report compliance summary

---

## **10.4 Security Hardening Checklist**

* TLS strictly 1.3
* mTLS agent ↔ FastAPI
* Rotate JWT signing keys
* Implement CRL or OCSP simulation
* Harden Redis + MySQL credentials
* Enable audit hashing

---

# 📊 **11. Observability & Resilience (Phase 10)**

---

## **11.1 Metrics**

* Command latency
* Queue depth
* Agent uptime
* OTA success rate

---

## **11.2 Logging**

* Structured logs
* Trace IDs across all services

---

## **11.3 Alerts**

* Device offline
* Risk score above threshold
* Update failures
* Tamper detection
* Backpressure conditions

---

## **11.4 DLQ & retries**

* Per-device DLQ streams
* Exponential backoff
* Operator facing remediation UI

---

# 🚀 **12. Deployment (Phase 11)**

---

## **12.1 Local dev environment**

Using Docker Compose:

* Laravel
* FastAPI
* Redis
* MySQL
* MinIO
* Agent simulator

---

## **12.2 Production**

Use Kubernetes:

* Horizontal scaling of FastAPI
* Laravel in HA mode
* Redis cluster or Sentinel
* MinIO / S3 backend
* Secrets via Vault or KMS

---

## **12.3 CI/CD**

Deploy pipelines:

* Push to main → test → build → deploy
* Secure build for C/C++ components
* Scan Docker images

---

# 🧪 **13. Final Integration & Verification (Phase 12)**

---

## **13.1 Full E2E test suite**

Covers:

* Pairing
* Command lifecycle
* OTA update
* Telemetry pipeline
* Policy updates
* Error cases

---

## **13.2 Chaos & fault testing**

Simulate:

* Network drops
* Redis failures
* Agent crashes
* KernelService errors
* Expired JWTs
* Revoked device cert
* OTA mid-download failures

---

## **13.3 Academic Report Deliverables (optional)**

* Architecture diagrams
* Flow charts
* Security analysis
* Performance metrics
* Observability dashboards

---

# 🎉 **Development Flow Complete**

