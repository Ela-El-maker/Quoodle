# 🧪 Quoodle Testing Scripts

This directory contains automation scripts for development, testing, and validation of the Quoodle system.

## 📋 Available Scripts

### **setup_dev.sh**

One-click setup script for the complete Quoodle development environment.

```bash
./scripts/setup_dev.sh
```

**What it does:**

- Validates Docker and Docker Compose installation
- Creates necessary `.env` files for Laravel and FastAPI services
- Builds and starts all containers (Laravel, FastAPI, MySQL, Redis)
- Verifies service health and provides access URLs

**Services started:**

- Control Plane (Laravel): http://localhost:8080
- Gateway (FastAPI): http://localhost:8000
- Database (MySQL): localhost:3307
- Redis: localhost:6379

### **run_e2e_full.sh**

Comprehensive end-to-end test runner that validates the complete Quoodle system.

```bash
./scripts/run_e2e_full.sh [runs] [seed]
```

**Parameters:**

- `runs`: Number of test iterations (default: 3)
- `seed`: Random seed for reproducible testing (default: 1337)

**What it validates:**

- ✅ User registration and JWT authentication
- ✅ Device pairing flow (init → request → confirm)
- ✅ WebSocket connections and agent authentication
- ✅ Command enqueuing, delivery, and execution
- ✅ Telemetry data transmission
- ✅ Command completion tracking

**Outputs:**

- Test logs: `logs/e2e/e2e_TIMESTAMP.jsonl`
- Metadata: `logs/e2e/e2e_TIMESTAMP_meta.txt`

### **Individual Test Scripts**

#### **test_api_auth.sh**

Tests the Laravel API authentication endpoints.

```bash
./scripts/test_api_auth.sh
```

#### **test_telemetry_worker.sh**

Tests the telemetry worker functionality.

```bash
./scripts/test_telemetry_worker.sh
```

## 🔧 Environment Variables

The E2E tests support the following environment variables:

```bash
LARAVEL_BASE_URL=http://localhost:8080
FASTAPI_BASE_URL=http://localhost:8000
TEST_USER_EMAIL=test@example.com
TEST_USER_PASSWORD=password
POLICY_HASH="sha256:4058fa9b252a07e03ee6ac2585e6424973427f953b6763b48679b61acafe49d2"
POLICY_VERSION="2026-01-21"
```

## 📊 Test Results

Latest validation results (January 21, 2026):

- **Status**: ✅ PASS (All 3 runs successful)
- **Coverage**: Complete end-to-end flow validated
- **Performance**: Sub-second response times for all operations
- **Security**: All cryptographic signatures verified

## 🚀 Quick Validation

To quickly validate your Quoodle setup:

```bash
# 1. Setup environment
./scripts/setup_dev.sh

# 2. Run E2E tests
./scripts/run_e2e_full.sh

# 3. Check results
tail -f logs/e2e/*.jsonl | jq '.result'
```
