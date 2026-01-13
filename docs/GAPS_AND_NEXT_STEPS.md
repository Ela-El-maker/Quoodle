# 📋 GAPS & NEXT STEPS

This document captures the **current state of Quoodle**, identifies **blocking and non-blocking gaps**, and defines a **clear, prioritized roadmap** to move the system from its current research-grade scaffold into a production-ready platform.

---

## 🔴 5. GAPS & NEXT STEPS

### **Critical Gaps (Blocking)**

| #   | Component   | Gap                                   | Impact                    | Priority    |
| --- | ----------- | ------------------------------------- | ------------------------- | ----------- |
| 1   | **Kernel**  | Dispatcher routes only 2/14 opcodes   | 12 commands unreachable   | 🔴 Critical |
| 2   | **Kernel**  | CMakeLists.txt missing 5 source files | Won't compile all opcodes | 🔴 Critical |
| 3   | **Laravel** | No JWT auth middleware                | API routes unprotected    | 🔴 Critical |
| 4   | **Agent**   | No controller signature verification  | Commands can be spoofed   | 🔴 Critical |
| 5   | **Agent**   | IOCTL request schema incomplete       | Audit trail broken        | 🟡 High     |

---

### **High Priority Gaps**

| #   | Component | Gap                             | Impact                   | Priority |
| --- | --------- | ------------------------------- | ------------------------ | -------- |
| 6   | Agent     | No reconnection with backoff    | Unreliable connection    | 🟡 High  |
| 7   | Agent     | No kernel response verification | Trust boundary broken    | 🟡 High  |
| 8   | Mobile    | No QR camera scanning           | Manual pairing only      | 🟡 High  |
| 9   | FastAPI   | Workers are empty stubs         | No background processing | 🟡 High  |
| 10  | Infra     | CI/CD pipelines are stubs       | No automated deployment  | 🟡 High  |

---

### **Medium Priority Gaps**

| #   | Component | Gap                              |
| --- | --------- | -------------------------------- |
| 11  | Agent     | SQLite queue is in-memory        |
| 12  | Agent     | OTA download not implemented     |
| 13  | Kernel    | Attestation returns stub data    |
| 14  | Kernel    | Tamper check uses hardcoded hash |
| 15  | Mobile    | WebSocket handling incomplete    |
| 16  | Mobile    | No push notifications            |
| 17  | Laravel   | OTA release flow is stub         |
| 18  | FastAPI   | Redis integration is fake        |
| 19  | Infra     | K8s missing Services, Secrets    |
| 20  | Infra     | Terraform missing VPC, EKS       |

---

## 🗺️ 6. PRIORITIZED ROADMAP

### **Phase 1: Kernel + Agent Integration (Week 1–2)**

| Task | Component | Effort | Deliverable                                 |
| ---- | --------- | ------ | ------------------------------------------- |
| 1.1  | Kernel    | 2h     | Wire all 14 opcodes in dispatcher           |
| 1.2  | Kernel    | 30m    | Add missing sources to CMakeLists.txt       |
| 1.3  | Kernel    | 2h     | Implement request signature verification    |
| 1.4  | Agent     | 4h     | Complete IOCTL request schema               |
| 1.5  | Agent     | 2h     | Implement controller signature verification |
| 1.6  | Agent     | 2h     | Implement kernel response verification      |
| 1.7  | Both      | 2h     | End-to-end integration test                 |

**🎯 Milestone 1:**
Agent can send all 14 commands to Kernel with a full, verifiable signature chain.

---

### **Phase 2: Security Hardening (Week 2–3)**

| Task | Component | Effort | Deliverable                           |
| ---- | --------- | ------ | ------------------------------------- |
| 2.1  | Laravel   | 4h     | JWT auth middleware for API routes    |
| 2.2  | Laravel   | 2h     | User role assignment                  |
| 2.3  | Agent     | 3h     | Reconnection with exponential backoff |
| 2.4  | Agent     | 4h     | Replace in-memory queue with SQLite   |
| 2.5  | FastAPI   | 2h     | Real Redis integration                |
| 2.6  | All       | 4h     | Security audit of signature flows     |

**🎯 Milestone 2:**
Full cryptographic trust chain verified end-to-end.

---

### **Phase 3: Mobile + UX (Week 3–4)**

| Task | Component | Effort | Deliverable                   |
| ---- | --------- | ------ | ----------------------------- |
| 3.1  | Mobile    | 4h     | Implement QR camera scanning  |
| 3.2  | Mobile    | 4h     | WebSocket real-time handling  |
| 3.3  | Mobile    | 4h     | Push notification integration |
| 3.4  | Mobile    | 4h     | Offline mode with caching     |
| 3.5  | Mobile    | 4h     | Write unit tests              |

**🎯 Milestone 3:**
Mobile app can pair via QR and receive real-time updates.

---

### **Phase 4: OTA + Attestation (Week 4–5)**

| Task | Component | Effort | Deliverable                    |
| ---- | --------- | ------ | ------------------------------ |
| 4.1  | Agent     | 8h     | OTA download manager           |
| 4.2  | Agent     | 4h     | Package signature verification |
| 4.3  | Kernel    | 8h     | Real TPM attestation           |
| 4.4  | Kernel    | 4h     | Real tamper check hashes       |
| 4.5  | Laravel   | 4h     | Complete OTA release flow      |

**🎯 Milestone 4:**
OTA updates work end-to-end with rollback support.

---

### **Phase 5: Production Readiness (Week 5–6)**

| Task | Component | Effort | Deliverable                            |
| ---- | --------- | ------ | -------------------------------------- |
| 5.1  | FastAPI   | 8h     | Implement all workers                  |
| 5.2  | Infra     | 4h     | Complete Dockerfiles                   |
| 5.3  | Infra     | 8h     | K8s manifests with Services, Secrets   |
| 5.4  | Infra     | 8h     | CI/CD pipelines                        |
| 5.5  | Infra     | 4h     | Prometheus alerts + Grafana dashboards |
| 5.6  | All       | 8h     | Load testing + performance tuning      |

**🎯 Milestone 5:**
System is deployable to production.

---

## 💡 7. RECOMMENDATIONS

### **Debugging Tips**

```bash
# FastAPI: Enable detailed logging
export LOG_LEVEL=DEBUG
uvicorn app.main:app --log-level debug

# Laravel: Enable query logging
DB_LOG_QUERIES=true php artisan serve

# Agent: Build with debug symbols
cmake -DCMAKE_BUILD_TYPE=Debug ..

# Named pipe debugging (Windows)
Get-ChildItem \\.\pipe\ | Where-Object { $_.Name -like "*Kernel*" }
```

---

### **Verification Commands**

```bash
# Verify JWKS endpoint
curl http://localhost:8080/.well-known/jwks.json | jq

# Verify FastAPI health
curl http://localhost:8000/health

# Verify WebSocket (wscat)
wscat -c ws://localhost:8000/agent

# Verify Ed25519 key pair
python3 -c "from nacl.signing import SigningKey; k=SigningKey.generate(); print(k.encode().hex())"
```

---

### **Security Checklist**

| Item | Status                              | Action         |
| ---- | ----------------------------------- | -------------- |
| ✅   | Ed25519 signing implemented         | —              |
| ✅   | Canonical JSON deterministic        | —              |
| ✅   | Replay protection (seq + timestamp) | —              |
| ⚠️   | JWT middleware missing              | Add to Laravel |
| ⚠️   | Controller sig verification         | Add to Agent   |
| ⚠️   | Named pipe security descriptor      | Add ACL        |
| ❌   | Certificate pinning                 | Add to Mobile  |
| ❌   | Rate limiting                       | Add to Laravel |

---

### **Canonical JSON Rules**

All components **must** follow these rules for signature compatibility:

1. UTF-8 encoding, no BOM
2. Sort object keys lexicographically
3. No trailing commas
4. Numbers as strings if precision matters
5. Remove insignificant whitespace
6. Normalize booleans to lowercase

---

## 📈 SUMMARY DASHBOARD

| Metric                     | Current | Target |
| -------------------------- | :-----: | :----: |
| **Kernel opcodes wired**   |  2/14   | 14/14  |
| **Agent sig verification** |   0%    |  100%  |
| **Laravel API protected**  |   0%    |  100%  |
| **Mobile QR scanning**     |   ❌    |   ✅   |
| **Test coverage**          |  ~25%   |  80%   |
| **CI/CD automation**       |   0%    |  100%  |

---
