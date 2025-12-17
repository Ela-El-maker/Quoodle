# Kernel Driver (planned)

This directory will contain the kernel-mode driver (KMDF) sources that expose IOCTLs
used by the `KernelService` privileged executor. For Phase 1 we keep a user-mode
service implementation; a KMDF driver is planned for tighter privilege separation.

Planned files:
- `driver.c` / `DriverEntry` skeleton
- INF and signing instructions
- build scripts (`build_driver.ps1` is provided at repository root)

Driver development notes:
- Development & testing require test-signing or a signed driver.
- Keep IOCTL surface minimal and validate all inputs in kernel-mode.
