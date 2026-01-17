# 📋 GAPS & NEXT STEPS (v2.0)

**Date**: 2026-01-18
**Status**: ACTIVE / AUDITED
**Auditor**: System Architect

This document captures the **verified state of Quoodle**, identifies **blocking gaps**, and defines a **prioritized roadmap** to move from `Prototype` to `Beta`.

---

## 🛑 1. END-TO-END FLOW ANALYSIS

We evaluated the primary "Command Lifecycle" flow: `Mobile -> Laravel -> FastAPI -> Agent -> Kernel`.

| Segment | Status | Root Cause | Impact |
| :--- | :--- | :--- | :--- |
| **Mobile -> Laravel** | 🟡 **Partially Working** | Auth works, but `POST /command` API is unprotected (No JWT Middleware). | Anyone can issue commands if they know the UUID. |
| **Laravel -> FastAPI** | 🟡 **Partially Working** | Dispatch logic exists, but `X-Laravel-Signature` verification is disabled/missing in FastAPI. | Attackers can spoof commands directly to Gateway. |
| **FastAPI -> Agent** | ✅ **Working** | Websocket delivery works reliably. | (None) |
| **Agent -> Kernel** | 🔴 **CRITICAL FAILURE** | Agent does **not verify** Control Plane signature. Agent passes unsigned/spoofed commands to Kernel. | **TOTAL SECURITY BYPASS**. Any network actor can command the device. |
| **Kernel Execution** | 🔴 **CRITICAL FAILURE** | Dispatcher `switch` statement handles only 2 of 14 opcodes. | 85% of features (Lock, Wipe, Update) silently fail. |
| **Telemetry (Return)** | 🟡 **Partially Working** | Data reaches Redis, but no workers exist to drain Redis -> MySQL. | Telemetry is lost in RAM; dashboard shows nothing. |

---

## 🔴 2. CRITICAL GAPS (BLOCKING)

**Criterion**: Security vulnerability or Feature-breaking bug.

| # | Component | Gap | Status | Effort |
| :--- | :--- | :--- | :--- | :--- |
| **1-CRIT** | **Agent** | **No Signature Verification**. Agent receives `COMMAND_DELIVERY` but skips Ed25519 check. | 🔴 **Open** | 4h |
| **2-CRIT** | **Kernel** | **Missing Opcodes**. Only `EXEC_PING` and `EXEC_GET_PROCESS_LIST` are wired. All others return default/error. | 🔴 **Open** | 4h |
| **3-CRIT** | **Control Plane** | **Unprotected API**. `routes/api.php` has no `auth:sanctum` middleware on critical endpoints. | 🔴 **Open** | 2h |
| **4-CRIT** | **Kernel** | **Missing Sources**. `CMakeLists.txt` references files that don't exist, preventing build of full opcode set. | 🔴 **Open** | 1h |
| **5-CRIT** | **Gateway** | **No Persistence**. Redis logic is mocked/in-memory. Gateway restart = lost telemetry. | 🔴 **Open** | 6h |

---

## 🟡 3. HIGH PRIORITY GAPS (BETA BLOCKERS)

**Criterion**: Stability or Usability issue.

| # | Component | Gap | Status | Effort |
| :--- | :--- | :--- | :--- | :--- |
| 6 | **Agent** | No exponential backoff on WSS reconnect. DDoS risk to Gateway. | 🟡 Pending | 3h |
| 7 | **Mobile** | QR Code Camera scanning is stubbed. Manual token entry only. | 🟡 Pending | 4h |
| 8 | **Gateway** | Missing `worker` processes to consume Redis streams and write to MySQL. | 🟡 Pending | 8h |
| 9 | **Infra** | No Docker Compose for local full-stack dev. | 🟡 Pending | 4h |
| 10 | **Control Plane** | CA Private Key is stored on disk/repo (Simulated). | 🟡 Pending | 2h |

---

## 🗺️ 4. PRIORITIZED ROADMAP

### **Phase 1: Security & Core Logic (Week 1)**
*Focus: Fixing the Red criticals to establish a secure, working "Happy Path".*

| Task | Component | Action |
| :--- | :--- | :--- |
| 1.1 | **Agent** | Implement `Ed25519_Verify(CmdEnvelope)` loop. **(Blocker)** |
| 1.2 | **Kernel** | Implement `switch(opcode)` for all 14 types. |
| 1.3 | **Laravel** | Apply `auth` middleware to `/api/commands`. |
| 1.4 | **Gateway** | Enforce `X-Laravel-Signature` check on dispatch endpoint. |
| 1.5 | **All** | Verify "Lock Screen" command end-to-end. |

### **Phase 2: Reliability & Persistence (Week 2)**
*Focus: Making the system survive restarts and network drops.*

| Task | Component | Action |
| :--- | :--- | :--- |
| 2.1 | **Agent** | Implement Exponential Backoff (1s -> 60s) for WSS. |
| 2.2 | **Gateway** | Replace in-memory Redis mock with `aioredis` + real Redis. |
| 2.3 | **Gateway** | Create `Worker` service to drain Telemetry -> MySQL. |
| 2.4 | **Mobile** | Implement Camera plugin for QR scanning. |

### **Phase 3: Operations & Updates (Week 3)**
*Focus: OTA and Telemetry visualization.*

| Task | Component | Action |
| :--- | :--- | :--- |
| 3.1 | **Agent** | Implement `STAGE_UPDATE` download logic. |
| 3.2 | **Kernel** | Implement `COMMIT_UPDATE` file swap logic. |
| 3.3 | **Laravel** | Build "Release Management" UI for uploading payloads. |
| 3.4 | **Mobile** | Render Telemetry charts from API data. |

---

## 🛠️ 5. VERIFICATION & TESTING

### **5.1 Security Checklist** (Updated)

| Check | Requirement | Status | Verification Command |
| :--- | :--- | :--- | :--- |
| **Command Sig** | Agent REJECTS unsigned envelopes | ❌ Fail | Send raw JSON via `wscat`; Agent currently accepts it. |
| **API Auth** | Laravel REJECTS unauthenticated POST | ❌ Fail | `curl -X POST /api/commands` works without Bearer token. |
| **TLS** | All traffic over TLS 1.3 | ✅ Pass | Enforced by config (but self-signed in dev). |
| **Tamper** | Kernel detects hollowed Agent | ⚠️ Stub | Returns hardcoded "OK". |
| **Replay** | Kernel rejects replayed IOCTL | ⚠️ Partial | Sequence check exists but state is volatile (RAM only). |

### **5.2 Verification Commands**

**Verify Command Signature (Agent)**
```bash
# 1. Send garbage signature
wscat -c ws://localhost:8000/agent -x '{"type":"COMMAND_DELIVERY", "sig":"invalid", ...}'
# EXPECT: {"type":"ERROR", "code":"INVALID_SIGNATURE"}
# ACTUAL: Agent executes command (FAIL)
```

**Verify API Auth (Laravel)**
```bash
# 1. POST without token
curl -X POST http://localhost/api/commands -d '{"method":"lock"}'
# EXPECT: 401 Unauthorized
# ACTUAL: 200 OK (FAIL)
```

---

## 💡 6. RECOMMENDATIONS

1.  **Stop Feature Development**: Do not build "Push Notifications" or "New Opcodes" until the **Phase 1** security fix is deployed. The system is currently "Insecure by Design" due to implementation bugs.
2.  **Centralized Logging**: Add a strict audit log format. Currently, if signature verification fails, it is just dropped. It should be logged as a `SECURITY_EVENT`.
3.  **Developer Experience**: Create a `./dev.sh` script that spins up the full stack (Laravel + MySQL + Redis + Gateway) so devs can test signatures locally.
