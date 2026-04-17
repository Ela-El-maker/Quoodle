# Quoodle

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-yellow.svg)]()
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-blue.svg)]()
[![Backend: Laravel](https://img.shields.io/badge/Backend-Laravel%2012-red.svg)]()
[![Gateway: FastAPI](https://img.shields.io/badge/Gateway-FastAPI-009688.svg)]()
[![Mobile: Flutter](https://img.shields.io/badge/Mobile-Flutter-02569B.svg)]()
[![Crypto: Ed25519](https://img.shields.io/badge/Crypto-Ed25519-black.svg)]()

Quoodle is a zero-trust remote device operations platform. It delivers signed commands from operator surfaces (web and mobile) through a policy and audit chain to endpoint agents that enforce execution boundaries with kernel or privileged backends.

## 1. System Overview

Core flow:

`Operator (Web/Mobile) -> Control Plane (Laravel) -> Gateway (FastAPI) -> Agent (Windows/Linux) -> Kernel Guard`

Return path:

`Kernel/Agent Result -> Gateway -> Control Plane -> UI/Mobile`

System guarantees:

- Commands are signed and verified end-to-end.
- Device identity is explicit and auditable.
- Pairing controls ownership before high-trust operations.
- Operator actions and agent receipts are persisted for audit trails.

## 2. Component Map

| Directory | Runtime | Responsibility |
| --- | --- | --- |
| `quoodle-control-plane` | Laravel / PHP 8.4 | Identity, pairing, RBAC, command authorization, audit persistence |
| `quoodle-control-plane-ui` | Next.js / React | Operator and viewer web console |
| `quoodle-gateway` | FastAPI / Python 3.11 | WS agent broker, dispatch fanout, webhook bridge |
| `quoodle-agent-windows` | C++23 / MSVC + WinUI | Windows service agent + UI companion |
| `quoodle-agent-linux` | C++17 / C + Python | Linux agent + privileged daemon + CLI/UI |
| `quoodle-kernel-guard` | C/C++ | Windows kernel driver and Linux privileged execution guard |
| `quoodle-mobile-client` | Flutter / Dart | Mobile operator app (auth, pairing, commanding, telemetry) |
| `quoodle-infra` | Terraform / Helm / K8s | Provisioning and deployment assets |
| `scripts` | Bash / PowerShell | Local setup, e2e runners, automation |

## 3. Local Environment Prerequisites

Host requirements:

- Docker Desktop with Compose
- Git
- Windows: Visual Studio C++ toolchain + CMake (for `quoodle-agent-windows`)
- Linux toolchain (for `quoodle-agent-linux` development)
- .NET SDK 8+ (Windows UI companion)
- Node.js 20+ (control plane UI)
- Flutter SDK (mobile client)

## 4. Local Startup (Backend Core)

From repo root:

```powershell
cd C:\Users\felix\Work-Force\Quoodle
Copy-Item .env.example .env -Force
docker compose --env-file .env up -d --build
docker compose ps
```

Expected services:

| Service | URL |
| --- | --- |
| Control Plane UI | `http://localhost:3000` |
| Control Plane API | `http://localhost:8088` |
| Gateway | `http://localhost:8000` |
| MySQL | `localhost:3307` |
| Redis | `localhost:6379` |

## 5. Windows Agent Bring-Up

1. Build `quoodle-agent-windows` agent binary.
2. Install service with `scripts/install_agent_service.ps1`.
3. Verify service is `RUNNING`.
4. Build and launch `ui-companion`.
5. Pair from web UI (token or QR).
6. Confirm device ownership.
7. Execute smoke commands (`collect_system_info`, `list_processes`).

See component READMEs for exact commands.

## 6. Pairing and Ownership Model

Pairing states:

- Unclaimed: device visible for claim workflow.
- Pending pairing: token/QR handshake started.
- Paired but not authenticated: credentials staged, runtime reconnect pending.
- Online authenticated: ready for command execution.

Ownership confirmation ties device identity to operator account after pairing challenge completion.

## 7. Command Lifecycle

1. Operator submits command.
2. Control plane validates authorization and signs envelope.
3. Gateway verifies request contract and routes to device channel.
4. Agent verifies signature and policy context.
5. Agent executes or forwards to kernel guard.
6. Result/receipt returns through gateway to control plane.
7. UI surfaces trace, status, and output.

## 8. Security Model

- Ed25519 signatures protect command integrity.
- Replay and TTL protections prevent stale reuse.
- Device identity and pairing state gate execution.
- Privileged execution is isolated (kernel driver / privileged daemon).
- Service-first runtime model keeps endpoint agent alive independent of UI process.

## 9. Testing and Validation

From repo root:

```powershell
# Full Windows ring0 e2e
pwsh .\scripts\run_windows_ring0_e2e.ps1

# Control plane tests
cd .\quoodle-control-plane
php artisan test

# Gateway tests
cd ..\quoodle-gateway
pytest
```

## 10. Operational Troubleshooting (Quick)

Common checks:

- `docker compose ps`
- `sc.exe query QuoodleAgent`
- gateway logs: `docker compose logs --tail=200 gateway`
- runtime identity files under `C:\ProgramData\Quoodle`
- UI bridge status via named pipe `QuoodleAgentUiBridge`

If command traces stall at queued or dispatch phases, verify device auth state first before checking command handlers.

## 11. Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## 12. License

[MIT](LICENSE)
