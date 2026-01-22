# 📘 **Quoodle**

### _Secure Device Control System • Research Sandbox_

> [!NOTE]
> **Status:** Active Development (Phases 1-3 Complete) ✅ **Fully Tested & Validated**
> **Latest Feature:** Full Docker Dev Stack & One-Click Setup with E2E Testing

## 🧭 **Overview**

![alt text](image.png)

**Quoodle** is a cryptographically secure platform enabling mobile users to remotely monitor, manage, and control Windows devices. Designed for security research and academic simulation, it mimics enterprise MDM/EDR architectures with strict "Zero Trust" principles.

### **Core Components**

| Component                 | Role                                                                         | Tech Stack            |
| ------------------------- | ---------------------------------------------------------------------------- | --------------------- |
| **quoodle-mobile-client** | User UI: Pairing, Telemetry, Command Issuance                                | Flutter               |
| **quoodle-control-plane** | Identity Provider (IdP), Policy Engine, Audit Log, Command Signing Authority | Laravel (PHP 8.4)     |
| **quoodle-gateway**       | Real-time WSS Hub, Telemetry Ingestion, Command Routing                      | FastAPI (Python 3.11) |
| **quoodle-agent-windows** | Device Agent: Connects to Gateway, Enforces Commands                         | C++23                 |
| **quoodle-kernel-guard**  | Kernel Service: Privileged Execution, Anti-Tamper, IOCTL                     | C / C++               |
| **quoodle-infra**         | Infrastructure: Docker, K8s, Terraform                                       | DevOps                |

---

## 🚀 **Quick Start (Developer)**

We provide a **One-Click** setup script to spin up the entire backend stack (Laravel, FastAPI, Redis, MySQL) using Docker Compose.

### **Prerequisites**

- Docker & Docker Compose
- Helper tools: `curl`, `openssl` (optional)

### **Run the Stack**

```bash
# 1. Run the setup script
./scripts/setup_dev.sh
```

This will:

1.  Check your environment.
2.  Generate necessary `.env` files.
3.  Build and start all containers via `docker-compose`.

**Access Points:**

- **Control Plane:** [http://localhost:8080](http://localhost:8080)
- **Control Plane (HTTPS):** [https://localhost:8444](https://localhost:8444)
- **Gateway:** [http://localhost:8000](http://localhost:8000) (Health: `/health`)
- **Gateway (HTTPS):** [https://localhost:8443](https://localhost:8443) (Health: `/health`)

### **Test the System**

After setup, validate the complete system with our end-to-end test suite:

```bash
# Run comprehensive E2E tests (recommended)
./scripts/run_e2e_full.sh

# Or run the test harness directly
LARAVEL_BASE_URL=http://localhost:8080 \
FASTAPI_BASE_URL=http://localhost:8000 \
TEST_USER_EMAIL=test@example.com \
TEST_USER_PASSWORD=password \
POLICY_HASH="sha256:4058fa9b252a07e03ee6ac2585e6424973427f953b6763b48679b61acafe49d2" \
POLICY_VERSION="2026-01-21" \
python3 e2e_quoodle_harness.py
```

This validates:

- ✅ User registration & authentication
- ✅ Device pairing flow
- ✅ WebSocket connections & agent auth
- ✅ Command enqueuing & delivery
- ✅ Telemetry transmission
- ✅ Command completion & polling

---

## 🔒 **Security Features (Implemented)**

### **Phase 1: Security Hardening**

- **Fail-Secure Defaults**: Agent and Kernel default to strictly enforcing signature verification if configuration is missing.
- **Fail-Closed API**: Control Plane API requires JWT authentication for all command endpoints.
- **Explicit Logging**: Agent logs detailed cryptographic failure reasons (e.g., "Signature Invalid", "Key Missing") to aid debugging without compromising security.

### **Phase 2: Reliability & Persistence**

- **Telemetry Pipeline**: Gateway ingests device telemetry via Redis queues for persistence.
- **Exponential Backoff**: Agent implements jittered exponential backoff (1s -> 60s) for robust reconnection.
- **Production Checks**: Services warn aggressively if critical backing services (Redis) are missing in production mode.

---

## 🧪 **Testing & Validation**

The system includes comprehensive end-to-end testing to validate the complete secure device control flow:

### **E2E Test Suite**

- **Coverage**: User registration → Device pairing → WebSocket auth → Command execution → Telemetry
- **Validation**: All three runs must pass with proper cryptographic signatures and audit trails
- **Logging**: Structured JSON logs with trace IDs, timestamps, and detailed error reporting
- **Automation**: One-click testing via `./scripts/run_e2e_full.sh`

### **Test Results (Latest)**

```
✅ PASS: User registration and authentication
✅ PASS: Device pairing (init → request → confirm)
✅ PASS: WebSocket connections and agent authentication
✅ PASS: Command enqueuing, delivery, and execution
✅ PASS: Telemetry data transmission and persistence
✅ PASS: Command completion tracking and polling
```

**Status**: All systems operational and fully validated.

## 📂 **Repository Structure**

```
Quoodle/
├── quoodle-control-plane/  # Laravel Backend (PHP 8.4)
├── quoodle-gateway/        # FastAPI Gateway (Python 3.11)
├── quoodle-agent-windows/  # Windows Agent (C++23)
├── quoodle-kernel-guard/   # Kernel Service (C/C++)
├── quoodle-mobile-client/  # Flutter App
├── quoodle-infra/          # Infrastructure Configs
├── quoodle-scripts/        # Development Utilities & Key Generation
├── docs/                   # Architecture, Specs, Protocols
├── scripts/                # Dev Automation & E2E Testing
│   ├── setup_dev.sh        # One-click Docker environment setup
│   ├── run_e2e_full.sh     # Comprehensive E2E test runner
│   └── e2e_full_flow.py    # Test automation framework
├── e2e_quoodle_harness.py  # End-to-end test harness
├── docker-compose.yml      # Root orchestration
└── logs/                   # Test logs and audit trails
```

---

## 📚 **Documentation**

- **Architecture**: [docs/architecture/](docs/architecture/)
- **Specifications**: [docs/specs/](docs/specs/)
- **Onboarding**: [docs/onboarding/](docs/onboarding/)
- **Testing Logs**: [logs/e2e/](logs/e2e/) (Latest validation: January 21, 2026)

## 🤝 **Contribution**

This is an academic research project. Code style is enforced via `clang-format` (C++), `black` (Python), and `pint` (PHP). See `docs/onboarding/contribution_guide.md`.
