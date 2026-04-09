# Quoodle

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-yellow.svg)]()
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-blue.svg)]()
[![Backend: Laravel](https://img.shields.io/badge/Backend-Laravel%2012-red.svg)]()
[![Gateway: FastAPI](https://img.shields.io/badge/Gateway-FastAPI-009688.svg)]()
[![Mobile: Flutter](https://img.shields.io/badge/Mobile-Flutter-02569B.svg)]()
[![Crypto: Ed25519](https://img.shields.io/badge/Crypto-Ed25519-black.svg)]()

Zero-trust remote device management platform. Cryptographically signed commands flow from an operator's mobile app through a centralized control plane and real-time gateway down to hardened endpoint agents — every action verified, every result audited.

## Architecture

```
Mobile App ──▶ Control Plane ──▶ Gateway ──▶ Agent ──▶ Kernel Guard
   (Flutter)     (Laravel)       (FastAPI)   (C++)      (Driver/Daemon)
```

All commands are Ed25519-signed with nonce + TTL replay protection. Agents verify signatures locally before executing anything. Audit receipts flow back through the same chain.

## Components

| Directory               | Stack                    | Role                                                                    |
| ----------------------- | ------------------------ | ----------------------------------------------------------------------- |
| `quoodle-control-plane` | Laravel / PHP 8.4        | Identity, certificate authority, policy engine, command auth, audit log |
| `quoodle-control-plane-ui` | Next.js / React / TypeScript | Control plane frontend (replaces Laravel Blade UI)                       |
| `quoodle-gateway`       | FastAPI / Python 3.11    | WebSocket broker, signature verification, command routing               |
| `quoodle-agent-linux`   | C++17 / Python           | Endpoint agent + privileged daemon (Unix Domain Socket)                 |
| `quoodle-agent-windows` | C++23 / MSVC             | Endpoint agent + kernel driver communication (IOCTL)                    |
| `quoodle-kernel-guard`  | C/C++                    | Kernel driver (Windows) / privileged daemon (Linux)                     |
| `quoodle-mobile-client` | Flutter / Dart           | Operator app — pair devices, issue commands, view telemetry             |
| `quoodle-infra`         | Terraform / K8s / Docker | Deployment and infrastructure configuration                             |

## Quick Start

```bash
# Create centralized local env from template
cp .env.example .env

# Clone and set up the dev environment
./scripts/setup_dev.sh

# Or manually with Docker Compose
docker compose up -d --build
```

| Service       | URL                   |
| ------------- | --------------------- |
| Control Plane UI | <http://localhost:3000> |
| Control Plane | <http://localhost:8088> |
| Gateway       | <http://localhost:8000> |
| MySQL         | localhost:3307        |
| Redis         | localhost:6379        |

### Pair a Device

```bash
# Windows ring0 end-to-end pairing + command path
pwsh ./scripts/run_windows_ring0_e2e.ps1 -KeepAgentRunning
```

## Testing

```bash
# Windows ring0 end-to-end protocol validation
pwsh ./scripts/run_windows_ring0_e2e.ps1

# Control Plane unit tests
cd quoodle-control-plane && php artisan test

# Gateway tests
cd quoodle-gateway && pytest
```

## Documentation

| Path                 | Contents                                                             |
| -------------------- | -------------------------------------------------------------------- |
| `docs/architecture/` | Master architecture, threat model, key management, system diagrams   |
| `docs/protocols/`    | API endpoints, WebSocket protocol, command envelope spec, IOCTL spec |
| `docs/security/`     | Trust model, message signing and canonicalization                    |
| `docs/onboarding/`   | Environment setup, coding standards, contribution guide              |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
