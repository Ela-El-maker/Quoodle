# quoodle-kernel-guard

Kernel-level privileged executor. On Windows, this is a kernel driver (`.sys`) that accepts IOCTL requests from the agent. On Linux, it's a privileged daemon. Validates caller identity, enforces replay protection, routes capabilities, and produces tamper-resistant audit receipts.

**Stack:** C / C++ (WDM/WDF on Windows)

## Build & Run

### Windows (Kernel Driver)

**Prerequisites:** Windows Driver Kit (WDK 10), Visual Studio 2026 (or Build Tools with WDK integration), elevated PowerShell.

**Status:** KMDF transport hardening is active for the driver path while opcode coverage remains intentionally limited.

**KMDF transport (current phase):**
- Driver source: `driver/kmdf/quoodle_kmdf.c`
- Device path: `\\.\QuoodleKernel`
- Supported opcodes: `PING`, `REBOOT`, `SHUTDOWN`
- `LOCK_SCREEN` / `LOGOUT` return `not_supported`
- Monotonic sequence is enforced in-kernel
- Strict transport validation is enforced:
  - payload bounds/null-termination checks
  - timestamp skew gate
  - replay gate (`agent_sequence`)
- HMAC-SHA256 request verification + signed responses
- Device ACL is restricted to `SYSTEM + Administrators`
- Canonical project anchor: `driver/kmdf/quoodle_kmdf/quoodle_kmdf.vcxproj`
- Template split files (`Driver.c` / `Device.c` / `Queue.c`) are parked scaffolding in this phase and excluded from build.

**Canonical build/install workflow:**
```powershell
cd .\quoodle-kernel-guard

# 1) Build deterministic Release|x64 artifact
.\scripts\build_driver.ps1 -Configuration Release -Platform x64

# 2) Optional first-time test-signing enable
.\scripts\install_kmdf_driver.ps1 -TestSigning
# reboot once, then:
.\scripts\install_kmdf_driver.ps1 -HmacKey "<shared-secret>"

# 3) Verify service
sc.exe query QuoodleKernel
```

`build_driver.ps1` auto-detects VS 2026 + WDK task-version mismatch and applies compatibility build flags (`VisualStudioVersion=17.0`) while disabling package verification / test-sign / API validator / INF2CAT for local unblock builds. Use the full signing pipeline separately for production packages.

Canonical build artifact path:
`driver\kmdf\x64\Release\quoodle_kmdf.sys`

The install script writes the key to:
`HKLM\SYSTEM\CurrentControlSet\Services\QuoodleKernel\Parameters\HmacKey`

Agent runtime must provide the same key:
`QUOODLE_DRIVER_HMAC_KEY`

On successful install, script verification includes:
- service creation and running-state check,
- HMAC key registry write/readback validation,
- `\\.\QuoodleKernel` device open check from admin context.

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

- Exposes a single Device Object (`\Device\QuoodleKernel`) with ACL `SYSTEM + Administrators`
- Re-verifies signatures on IOCTL requests (HMAC-SHA256)
- Fixed-size structs across the kernel boundary
- Deny-by-default capability routing: if a capability isn't explicitly allowed, it doesn't exist
