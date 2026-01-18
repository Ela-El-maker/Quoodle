# 🛡️ quoodle-kernel-guard

**Role**: Execution / Enforcement (Kernel Mode)
**Tech Stack**: C/C++ (WDM/WDF Driver)
**Responsibility**: Privileged Execution, Tamper Resistance, Attestation.

---

## 📖 Overview

The `quoodle-kernel-guard` is the privileged kernel driver (`.sys`) ensuring that sensitive operations cannot be bypassed or spoofed by user-mode malware.

1.  **IOCTL Interface**: Accepts strictly defined opcodes from `quoodle-agent-windows`.
2.  **Tamper Check**: Monitors the Agent process to ensure it hasn't been hollowed or code-injected.
3.  **Attestation**: Generates TPM quotes and system integrity hashes for the Control Plane.

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
