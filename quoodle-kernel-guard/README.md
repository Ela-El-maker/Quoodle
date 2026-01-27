# 🛡️ quoodle-kernel-guard

**Role**: Execution / Enforcement (Kernel Mode)
**Tech Stack**: C/C++ (WDM/WDF Driver)

**Responsibility**: Privileged Execution, Tamper Resistance, Attestation, Audit Logging, Compliance Enforcement.

---

## 📖 Overview

The `quoodle-kernel-guard` is the privileged kernel driver (`.sys`) (Windows) or privileged daemon (Linux) ensuring that sensitive operations cannot be bypassed or spoofed by user-mode malware.

1.  **IOCTL/Privileged IPC Interface**: Accepts strictly defined opcodes from `quoodle-agent-windows` (Windows) or privileged IPC from `quoodle-agent-linux` (Linux).
2.  **Tamper Check**: Monitors the Agent process to ensure it hasn't been hollowed or code-injected.
3.  **Attestation**: Generates TPM quotes and system integrity hashes for the Control Plane.
4.  **Audit Logging**: Logs all privileged actions for compliance and forensic review.
5.  **Compliance Enforcement**: Enforces policy and anti-replay at the lowest level.

## Windows Kernel Service Architecture (Ring-0 Consequence Layer)

The Windows Kernel Service is the final authority in the Quoodle system.

Everything above it is permission.
Everything here is irreversible consequence.

If this layer is wrong, the OS is owned.

## Architectural Overview

                 (User-mode boundary)

┌──────────────────────────────────────────────────────────┐
│ Windows Agent (User Mode) │
│ - Runs as standard service │
│ - No admin token │
│ - No SeDebugPrivilege │
│ - Cannot call OS power directly │
└───────────────▲──────────────────────────────────────────┘
│ DeviceIoControl (IOCTL)
│ Fixed structs only
│ METHOD_BUFFERED
┌───────────────┴──────────────────────────────────────────┐
│ WINDOWS KERNEL DRIVER (Ring 0) │
│ │
│ [1] Driver Entry & Dispatch │
│ - IRP_MJ_CREATE │
│ - IRP_MJ_DEVICE_CONTROL │
│ - IRP_MJ_CLOSE │
│ │
│ [2] Caller Identity Gate │
│ - Validate process token │
│ - Verify service SID │
│ - Optional Code Integrity policy │
│ │
│ [3] Replay / TTL Guard │
│ - Per-device monotonic sequence │
│ - Command ID LRU cache │
│ - Kernel time window enforcement │
│ │
│ [4] Capability Router │
│ - IOCTL → Capability ID │
│ - Allowlist only │
│ - Parameter bounds validation │
│ │
│ [5] Execution Layer │
│ - Native kernel ops (rare) │
│ - Or brokered call to trusted user-mode helper │
│ │
│ [6] Audit & Telemetry │
│ - ETW events │
│ - Kernel trace buffer │
│ - Signed receipt returned to agent │
└──────────────────────────────────────────────────────────┘
(Ring-0 primitives)

Core Design Rules (Non-Negotiable)

1. No Strings Cross the Boundary

Only fixed-size structs.

No JSON.
No pointers.
No dynamic memory from user input.

This alone prevents entire classes of exploits.

2. IOCTL Is a Capability, Not a Command

Each IOCTL maps to exactly one allowed capability.

Example:

IOCTL Code Capability Effect
IOCTL_QD_LOCK CAP_LOCK_SESSION Approve lock
IOCTL_QD_KILL CAP_TERMINATE_PROCESS Kill PID
IOCTL_QD_NETISO CAP_NETWORK_ISOLATION Toggle isolation

If it’s not explicitly allowed, it does not exist.

3. Kernel Driver Does NOT Trust the Agent

Even if:

agent is signed

agent is authenticated

agent has a valid command

The kernel still enforces:

identity

sequence

TTL

capability bounds

Detailed Component Breakdown
[1] Driver Entry & Dispatch

Registers device: \Device\Quoodle

Exposes symbolic link: \\.\Quoodle

Handles:

IRP_MJ_CREATE

IRP_MJ_DEVICE_CONTROL

IRP_MJ_CLOSE

No filesystem, no registry writes.

[2] Caller Identity Gate

Checks who is talking before what they want.

Typical checks:

Process SID == expected service SID

Token is not elevated user token

Optional: validate code signature of calling process

Optional: ensure caller is in expected session

Fail here → hard deny.

[3] Replay & TTL Guard (Kernel-Enforced)

Maintain last seen agent_sequence

Reject:

sequence ≤ last_sequence

expired TTL

duplicate command_id

All checks occur before capability routing

This prevents:

replay attacks

stale commands

time-shift abuse

[4] Capability Router

Single switch table:

switch (IoctlCode) {
case IOCTL_QD_LOCK:
return CapLockSession(req);
case IOCTL_QD_KILL:
return CapKillProcess(req);
default:
return STATUS_INVALID_DEVICE_REQUEST;
}

No fallthrough.
No extensibility without recompilation.

[5] Execution Layer

Two patterns:

A. Kernel-native (rare)

Used only when:

action is safe

action cannot be brokered

Example:

session lock signal

secure attention events

B. Brokered Execution (preferred)

Kernel:

validates

authorizes

signals trusted user-mode helper

User-mode helper:

executes OS-level tools

reports result back to kernel

This keeps kernel small and auditable.

[6] Audit & Telemetry

Every decision emits:

ETW event

kernel trace entry

signed receipt to agent

Captured fields:

command_id

capability

caller SID

allow/deny

execution time

No silent failures.

What the Windows Kernel Service Must Never Do

Parse JSON

Allocate user-provided pointers

Perform network I/O

Trust user-mode policy decisions

Execute arbitrary code paths

Teaching: Worst-Case Scenarios (Windows Kernel)

You can demonstrate:

Privilege escalation if caller identity isn’t checked

Replay execution if sequence isn’t persisted

Capability abuse if IOCTL routing is lax

System crash if unbounded params allowed

And then show:

“This is why kernel code must be boring.”

Practical Build Milestones (Windows Kernel)

Skeleton driver + device

Identity gate (SID validation)

Monotonic sequence enforcement

Capability routing table

One capability end-to-end:

CAP_LOCK_SESSION

ETW audit logging

Intentional failure toggles for labs

One-Line Mental Model

The Windows Kernel Service does not decide intent —
it decides whether the OS will obey.

## 🛠️ Build & Run

### Prerequisites

- Windows Driver Kit (WDK)
- Visual Studio 2022

### Setup

```bash
# Open solution in Visual Studio
start quoodle-kernel-guard.sln
# Build for target architecture (x64)
```

### Deployment

**Strictly for Test Signing Mode**:

```bash
bcdedit /set testsigning on
sc create QuoodleKernel binPath= "C:\Refresh\quoodle-kernel-guard.sys" type= kernel
sc start QuoodleKernel
```

## 🔐 Security Context

- **Attack Surface**: Exposes a single Device Object (`\Device\QuoodleKernel`) accessible only by the SYSTEM account.
- **Validation**: Re-verifies all signatures on IOCTL requests to prevent "confused deputy" attacks from the Agent.
