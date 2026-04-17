# quoodle-kernel-guard

Privileged execution boundary for Quoodle endpoint operations.

On Windows this is a KMDF kernel driver (`QuoodleKernel`). On Linux, equivalent privileged behavior is handled by the root daemon layer.

## 1. Architecture and Intent

Core intent:

- keep high-risk operations behind a minimal trusted interface
- validate integrity and sequencing before action
- return bounded machine-readable responses

## 2. Windows KMDF Design

### 2.1 Driver Surface

- device path: `\\.\QuoodleKernel`
- IOCTL entrypoints constrained to explicit opcode set
- ACLs restrict caller classes (SYSTEM/Administrators)

### 2.2 Protocol Features

- monotonic sequence checks to reduce replay
- request size and skew validation
- HMAC-SHA256 request verification
- structured signed response payloads

### 2.3 Capability Rollout

Only explicitly enabled opcodes are accepted. Unsupported operations fail closed with deterministic status.

## 3. Linux Privileged Boundary

Linux privileged daemon serves a similar role:

- root-bound execution scope
- controlled UDS protocol boundary
- explicit operation allowlist

## 4. Build and Install (Windows)

From `quoodle-kernel-guard`:

```powershell
.\scripts\build_driver.ps1 -Configuration Release -Platform x64
.\scripts\install_kmdf_driver.ps1 -TestSigning
# reboot once if test signing was newly enabled
.\scripts\install_kmdf_driver.ps1 -HmacKey "<shared-secret>"
sc.exe query QuoodleKernel
```

Expected artifact:

- `driver\kmdf\x64\Release\quoodle_kmdf.sys`

## 5. Key Synchronization Model

Shared key location:

- `HKLM\SYSTEM\CurrentControlSet\Services\QuoodleKernel\Parameters\HmacKey`

Agent and kernel layer must agree on key material to pass request verification.

## 6. Security Design Principles

- deny-by-default capability handling
- minimal exposed interface area
- strict input validation at privilege boundary
- deterministic failure semantics for auditability

## 7. Layout

- `driver/`: kernel driver source
- `attestation/`: integrity/attestation assets
- `integrity-checks/`: runtime hardening checks
- `rollback/`: recovery and rollback support
- `service/`: service-related support files
- `tests/`: validation coverage

## 8. Troubleshooting

### Driver Not Running

- verify signing mode and install success
- inspect `sc.exe query QuoodleKernel`

### IOCTL Open Failure

- verify caller privilege level
- verify device ACL and path

### Auth Mismatch

- verify HMAC key parity between registry and agent runtime config

### Unsupported Operation

- verify opcode is included in current rollout scope

## 9. Sequence Diagrams

### 9.1 Windows IOCTL Verification Path

```text
Agent Service        Kernel Driver (KMDF)         Device/OS Action
     |                         |                         |
     | IOCTL request           | validate seq/hmac       |
     |------------------------>|------------------------>|
     |                         | execute allowed opcode  |
     | structured response     |<------------------------|
     |<------------------------|                         |
```

### 9.2 Key Synchronization Check

```text
Installer/Ops         Registry Key              Agent Runtime
    |                     |                          |
    | write HmacKey       |                          |
    |-------------------->|                          |
    |                     | read on startup          |
    |                     |------------------------->|
    |                     | parity required          |
```
