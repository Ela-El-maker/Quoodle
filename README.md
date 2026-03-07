# Quoodle

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

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
| `quoodle-gateway`       | FastAPI / Python 3.11    | WebSocket broker, signature verification, command routing               |
| `quoodle-agent-linux`   | C++17 / Python           | Endpoint agent + privileged daemon (Unix Domain Socket)                 |
| `quoodle-agent-windows` | C++23 / MSVC             | Endpoint agent + kernel driver communication (IOCTL)                    |
| `quoodle-kernel-guard`  | C/C++                    | Kernel driver (Windows) / privileged daemon (Linux)                     |
| `quoodle-mobile-client` | Flutter / Dart           | Operator app — pair devices, issue commands, view telemetry             |
| `quoodle-infra`         | Terraform / K8s / Docker | Deployment and infrastructure configuration                             |

## Quick Start

```bash
# Clone and set up the dev environment
./scripts/setup_dev.sh

# Or manually with Docker Compose
docker compose up -d --build
```

| Service       | URL                   |
| ------------- | --------------------- |
| Control Plane | http://localhost:8088 |
| Gateway       | http://localhost:8000 |
| MySQL         | localhost:3307        |
| Redis         | localhost:6379        |

### Pair a Device

```bash
# Register + pair the Linux agent
python3 scripts/setup_linux_agent_secrets.py

# Install and start the agent service
./scripts/install_linux_agent_systemd.sh
```

## Testing

```bash
# End-to-end protocol validation
./scripts/run_e2e_full.sh

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
