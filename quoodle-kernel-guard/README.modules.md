# Kernel Service Modules

These directories organize privileged features that complement the user-mode agent and keep IOCTL surfaces minimal.

- `attestation/`: Kernel-level measurements, secure boot checks, and attestation report creation to back the user-mode claims.
- `rollback/`: Safe driver upgrade/rollback logic, versioned INF packages, and failure-handling routines.
- `integrity-checks/`: Periodic kernel integrity probes (code section hashing, config checks) and reporting hooks.
