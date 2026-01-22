# 📜 Protocol & API Specifications

The Quoodle system is defined by strict, canonical JSON specifications. These files are the source of truth for all inter-component communication.

> **Note**: Developers must not manually implement protocols; use the generated types or strictly adhere to these JSON definitions.

**Dispatch Contract**: Control Plane → Gateway command dispatch is canonical over HTTP `POST /api/v1/command/dispatch`. Redis streams may be used internally by the Gateway for buffering but are not a contract surface.

---

## 🏗️ Core Specifications Index

| Scope | JSON File | Description |
| :--- | :--- | :--- |
| **Agent ↔ Gateway** | [WindowsAgent ↔ FastAPI (WSS control channel).json](./WindowsAgent%20↔%20FastAPI%20(WSS%20control%20channel).json) | Persistent WebSocket protocol for real-time control, heartbeat, and telemetry. |
| **Mobile ↔ Control** | [Laravel ↔ Mobile App (REST + notifications).json](./Laravel%20↔%20Mobile%20App%20(REST%20+%20notifications).json) | REST API for user actions: Login, Pairing, Issuing Commands, Views. |
| **Agent ↔ Kernel** | [WindowsAgent ↔ KernelService Interface.json](./WindowsAgent%20↔%20KernelService%20Interface.json) | Local IOCTL interface for privileged operations (User Mode to Kernel Mode). |
| **Control ↔ Gateway** | [FastAPI ↔ Laravel (REST + Webhook Control Channel).json](./FastAPI%20↔%20Laravel%20(REST%20+%20Webhook%20Control%20Channel).json) | Backend signaling: Dispatching signed envelopes, syncing presence. |

---

## 📡 1. Agent ↔ Gateway (WSS)

**Protocol**: WebSocket over TLS 1.3
**Auth**: Agent-signed `AUTH` message (JWT)

### Message Types
| Type | Direction | Purpose |
| :--- | :--- | :--- |
| `AUTH` | ⬆️ | Agent establishes identity. |
| `HEARTBEAT` | ⬆️ | Periodic liveness check. |
| `TELEMETRY` | ⬆️ | Metrics (CPU, RAM, Risk) upload. |
| `COMMAND_DELIVERY` | ⬇️ | Gateway pushes signed command envelope. |
| `COMMAND_RESULT` | ⬆️ | Agent reports execution outcome. |
| `UPDATE_ANNOUNCE` | ⬇️ | Notify agent of OTA update. |

---

## 📱 2. Mobile ↔ Control Plane (REST)

**Protocol**: HTTPS (REST)
**Auth**: User JWT

### Key Endpoints
| Verb | Path | Purpose |
| :--- | :--- | :--- |
| `POST` | `/api/pair/init` | Start pairing session (returns QR metadata). |
| `POST` | `/api/pair/confirm` | Finalize pairing using token from QR scan. |
| `POST` | `/api/commands` | Issue a command to a specific device. |
| `GET` | `/api/devices/{id}/telemetry/latest` | View live device stats. |
| `GET` | `/api/devices/{id}/updates` | View OTA history. |

---

## 🛡️ 3. Agent ↔ Kernel (IOCTL)

**Protocol**: Local IOCTL
**Security**: All requests signed by Agent; validated by Kernel.

### Allowed Opcodes
| Opcode | Description |
| :--- | :--- |
| `EXEC_LOCK_SCREEN` | Lock the Windows user session. |
| `EXEC_REBOOT` | Restart the machine. |
| `EXEC_SHUTDOWN` | Power off the machine. |
| `STAGE_UPDATE` | Write update binary to protected staging area. |
| `EXEC_RUN_ATTESTATION` | Generate TPM quote and integrity hash. |
| `EXEC_RUN_TAMPER_CHECK` | Verify kernel memory integrity. |
