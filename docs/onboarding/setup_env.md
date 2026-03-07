# Environment Setup

## Recommended: Docker (Full Stack)

The fastest way to get the whole system running:

```bash
./scripts/setup_dev.sh
```

This starts Laravel, FastAPI, Redis, and MySQL in Docker containers with all configuration handled automatically. No local toolchain needed.

**Services after setup:**

| Service                 | URL                   |
| ----------------------- | --------------------- |
| Control Plane (Laravel) | http://localhost:8080 |
| Gateway (FastAPI)       | http://localhost:8000 |
| MySQL                   | localhost:3306        |
| Redis                   | localhost:6379        |

## Manual Setup (Component by Component)

### Prerequisites

| Tool        | Version | Used by                                                          |
| ----------- | ------- | ---------------------------------------------------------------- |
| PHP         | 8.4+    | quoodle-control-plane                                            |
| Composer    | 2.x     | quoodle-control-plane                                            |
| Python      | 3.11+   | quoodle-gateway                                                  |
| Node.js     | 18+     | quoodle-control-plane (Vite assets)                              |
| CMake       | 3.20+   | quoodle-agent-linux, quoodle-agent-windows, quoodle-kernel-guard |
| Flutter SDK | 3.0+    | quoodle-mobile-client                                            |
| Docker      | 20.10+  | Full stack orchestration                                         |

### Control Plane

```bash
cd quoodle-control-plane
composer install
cp .env.example .env        # edit DB credentials
php artisan key:generate
php artisan migrate
php artisan serve --port=8080
```

### Gateway

```bash
cd quoodle-gateway
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

### Linux Agent

```bash
cd quoodle-agent-linux
mkdir -p build && cd build
cmake .. && make
```

### Mobile Client

```bash
cd quoodle-mobile-client
flutter pub get
flutter run
```

## Ed25519 Key Generation

Generate development keypairs for agent/gateway signing:

```bash
python3 quoodle-scripts/generate_ed25519_keys.py
```

Set the output as environment variables — see [quoodle-scripts/README.md](../../quoodle-scripts/README.md) for details.

## Verification

After setup, run the E2E suite to confirm everything works:

```bash
./scripts/run_e2e_full.sh
```
