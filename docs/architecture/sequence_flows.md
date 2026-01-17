# 🔄 Sequence Flows

This document details the step-by-step logic for critical system operations.

## 1. Device Pairing (Trust Establishment)

The process of binding a raw `quoodle-agent-windows` to a `quoodle-mobile-client` user account.

```mermaid
sequenceDiagram
    autonumber
    participant Agent as quoodle-agent-windows
    participant Gateway as quoodle-gateway
    participant Control as quoodle-control-plane
    participant Mobile as quoodle-mobile-client

    Note over Agent: Device is Unpaired
    Agent->>Gateway: WSS Connect (Anonymous/Temp ID)
    Gateway-->>Agent: Challenge Token
    Agent->>Gateway: Sign(Challenge)
    Gateway->>Control: Register Pending Device
    
    Agent->>Agent: Generate Pairing Token
    Agent->>Agent: Display QR Code (Pairing Token)
    
    Note over Mobile: User Scans QR
    Mobile->>Control: POST /pair (Pairing Token, DeviceID)
    Control->>Control: Validate Token
    Control->>Control: Issue Device Certificate (Signed by CA)
    Control-->>Mobile: Success
    
    Control->>Gateway: Notify: Device Paired
    Gateway->>Agent: Send Certificate & Config
    
    Agent->>Agent: Store Cert in Secure Storage
    Agent->>Gateway: Reconnect (mTLS with new Cert)
    Note over Agent: Device is Trusted
```

---

## 2. Command Execution (Round Trip)

The path of a command from intent to verified execution.

```mermaid
sequenceDiagram
    autonumber
    participant Mobile as quoodle-mobile-client
    participant Control as quoodle-control-plane
    participant Gateway as quoodle-gateway
    participant Agent as quoodle-agent-windows
    participant Kernel as quoodle-kernel-guard

    Mobile->>Control: POST /command/issued (OpCode, Params)
    Control->>Control: AuthZ & Policy Check
    Control->>Control: Sign Command (Ed25519)
    Control->>Gateway: Dispatch Command Envelope
    
    Gateway->>Agent: WSS: COMMAND_DELIVERY
    
    Agent->>Agent: Verify Control Signature
    Agent->>Agent: Check Policy Cache
    
    Agent->>Kernel: IOCTL(OpCode, Params, Sig)
    Kernel->>Kernel: Verify Kernel-Mode Constraints
    Kernel->>Kernel: EXECUTE
    Kernel-->>Agent: Signed Result
    
    Agent->>Gateway: WSS: COMMAND_RESULT
    Gateway->>Control: Webhook: Result
    Control->>Mobile: Push Notification (Success)
```
