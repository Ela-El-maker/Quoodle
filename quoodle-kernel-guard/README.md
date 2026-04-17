# quoodle-kernel-guard

Privileged execution boundary for Quoodle endpoint operations.

On Windows this is a kernel driver (`QuoodleKernel`) accessed via IOCTL. On Linux this role is provided by the privileged daemon layer.

## 1. Responsibilities

- enforce privileged capability boundaries
- validate transport-level integrity for incoming requests
- execute allowed privileged opcodes only
- return bounded, structured responses for upstream verification

## 2. Windows Driver Scope

Current KMDF hardening phase includes:

- driver path: `driver/kmdf/quoodle_kmdf.c`
- device path: `\\.\QuoodleKernel`
- supported opcodes: `PING`, `REBOOT`, `SHUTDOWN`
- replay and monotonic sequence enforcement
- payload bounds and skew validation
- HMAC-SHA256 request verification and signed responses
- restrictive device ACL (`SYSTEM` + `Administrators`)

Unsupported opcodes intentionally return `not_supported` until staged rollout enables them.

## 3. Build and Install (Windows)

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

## 4. Key Synchronization

Install script writes HMAC key to:

- `HKLM\SYSTEM\CurrentControlSet\Services\QuoodleKernel\Parameters\HmacKey`

Agent must use matching value via runtime env/settings.

## 5. Security Model

- deny by default: unknown capability means no execution path
- strict structure validation at kernel boundary
- deterministic failure responses for policy/transport violations
- no userland UI or operator identity bypass in driver path

## 6. Project Layout

- `driver/` Windows driver source
- `attestation/` integrity and attestation components
- `integrity-checks/` runtime verification tooling
- `rollback/` rollback and recovery scaffolding
- `service/` service management support
- `tests/` validation coverage

## 7. Troubleshooting

- service missing: reinstall driver and verify signing mode
- IOCTL open failure: verify admin rights and ACL
- auth mismatch: verify shared HMAC key parity
- opcode unsupported: verify current rollout scope before testing command
