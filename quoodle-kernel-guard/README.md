# quoodle-kernel-guard

Kernel-level privileged executor. On Windows, this is a kernel driver (`.sys`) that accepts IOCTL requests from the agent. On Linux, it's a privileged daemon. Validates caller identity, enforces replay protection, routes capabilities, and produces tamper-resistant audit receipts.

**Stack:** C / C++ (WDM/WDF on Windows)

## Build & Run

### Windows (Kernel Driver)

**Prerequisites:** Windows Driver Kit (WDK), Visual Studio 2022

```bash
# Open and build in Visual Studio
start quoodle-kernel-guard.sln
```

**Test deployment (test signing only):**

```bash
bcdedit /set testsigning on
sc create QuoodleKernel binPath= "C:\path\to\quoodle-kernel-guard.sys" type= kernel
sc start QuoodleKernel
```

### Linux (Privileged Daemon)

Built as part of `quoodle-agent-linux`. See that component's README.

## Project Structure

```
driver/           # Kernel driver source (Windows)
attestation/      # TPM attestation and integrity verification
integrity-checks/ # Runtime integrity validation
rollback/         # Rollback and recovery mechanisms
service/          # Service management
tests/            # Driver and integration tests
```

## Security

- Exposes a single Device Object (`\Device\QuoodleKernel`) accessible only by SYSTEM
- Re-verifies all signatures on IOCTL requests — never trusts the agent blindly
- Fixed-size structs only across the kernel boundary — no JSON, no pointers, no dynamic allocation
- Deny-by-default capability routing: if a capability isn't explicitly allowed, it doesn't exist
