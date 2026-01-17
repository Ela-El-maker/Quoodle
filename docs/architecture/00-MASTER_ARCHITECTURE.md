# 🏛️ Quoodle Master Architecture

**Secure Device Control System**

This document serves as the authoritative entry point for the Quoodle platform architecture. It defines the high-level structure, component, and interaction flows for the system.

> **Note**: All component references in this document strictly follow the `quoodle-<role>` naming convention.

---

## 1. System Context

Quoodle is a research-grade platform designed to demonstrate secure, cryptographically verified remote management of Windows devices. It simulates a high-security Enterprise Mobility Management (EMM) or Endpoint Detection and Response (EDR) system.

The system is composed of five primary components with distinct trust boundaries:

| Component | Role | Tech Stack | Responsibility |
| :--- | :--- | :--- | :--- |
| **`quoodle-mobile-client`** | Client / Intent | Flutter | User interface for device pairing, command issuance, and telemetry visualization. |
| **`quoodle-control-plane`** | Control / Governance | Laravel (PHP) | Identity provider (IdP), Certificate Authority (CA), Policy Engine, and Audit Logging. **Root of Trust**. |
| **`quoodle-gateway`** | Transport / Gateway | FastAPI (Python) | High-performance WebSocket (WSS) hub for real-time device communication and telemetry ingestion. |
| **`quoodle-agent-windows`** | Execution (User Mode) | C++ | Persistent service on target devices. Manages WSS connection, verifies signatures, and relays commands to kernel. |
| **`quoodle-kernel-guard`** | Execution (Kernel) | C/C++ Driver | Privileged kernel driver (sys/sys) executing sensitive operations (IOCTL) and ensuring tamper resistance. |

---

## 2. Architecture Diagram

```mermaid
graph TD
    User((User)) -->|Interacts| Client[quoodle-mobile-client]
    
    subgraph Cloud Infrastructure
        Client -->|REST API| Control[quoodle-control-plane]
        Client -->|WSS / Push| Gateway[quoodle-gateway]
        
        Control <-->|Webhooks / Internal API| Gateway
        
        db[(MySQL / Redis)]
        Control --- db
        Gateway --- db
    end
    
    subgraph Target Device [Windows Endpoint]
        Agent[quoodle-agent-windows]
        Kernel[quoodle-kernel-guard]
        
        Agent <-->|WSS (mTLS)| Gateway
        Agent <-->|IOCTL| Kernel
    end
    
    %% Styles
    style Control fill:#f9f,stroke:#333,stroke-width:2px
    style Gateway fill:#bbf,stroke:#333,stroke-width:2px
    style Agent fill:#cfc,stroke:#333,stroke-width:2px
    style Kernel fill:#f66,stroke:#333,stroke-width:2px,color:white
```

---

## 3. Core Interactions

### 3.1 Trust & Pairing
The system uses a strict trust model rooted in `quoodle-control-plane`.
1. **Identity**: Devices are identified by certificates issued by the Control Plane CA.
2. **Pairing**: `quoodle-agent-windows` displays a QR code containing a secure token. `quoodle-mobile-client` scans this to bind the device to a user account.

### 3.2 Command Lifecycle
All administrative actions follow a signed path:
1. **Intent**: User issues command via `quoodle-mobile-client`.
2. **Authorization**: `quoodle-control-plane` validates permissions, enforces policy, and **signs** the command envelope.
3. **Dispatch**: `quoodle-gateway` routes the signed envelope to the specific `quoodle-agent-windows` via WSS.
4. **Verification**: `quoodle-agent-windows` verifies the signature against the Control Plane's public key.
5. **Execution**: Validated commands are passed to `quoodle-kernel-guard` via IOCTL for execution.
6. **Result**: Execution results are signed by the kernel/agent and returned upstream to the user.

---

## 4. Documentation Index

For deeper dives into specific areas:

- **[System Diagrams](./system_diagrams.md)**: Detailed visual flows for Pairing, Commands, and Updates.
- **[Sequence Flows](./sequence_flows.md)**: Step-by-step interaction logic.
- **[Security & Trust Model](../security/trust_model.md)**: Cryptographic details, key management, and threat models.
- **[API & Protocol Specs](../specs/README.md)**: Human-readable summaries of the JSON specifications.
