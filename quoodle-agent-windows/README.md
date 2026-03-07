# quoodle-agent-windows

Windows endpoint agent. Runs as a Windows service, connects to the gateway over WSS, verifies Ed25519 signatures, and forwards validated commands to the kernel driver via IOCTL.

**Stack:** C++23 (WinAPI, Boost.Asio)

## Build & Run

**Prerequisites:** CMake 3.20+, Visual Studio 2022, Boost, OpenSSL

```bash
mkdir build && cd build
cmake ..
cmake --build . --config Release
```

```bash
./quoodle-agent-windows.exe --config config.json
```

## Device Identity

Persists to `C:/ProgramData/Quoodle/device_id` (auto-generated on first run).

**Override order:** `AGENT_DEVICE_ID` env → `AGENT_DEVICE_ID_FILE` env → default path.

## Project Structure

```
src/         # Agent source (WSS client, crypto, command state machine)
include/     # Headers
attestation/ # TPM attestation module
quarantine/  # Network isolation module
recovery/    # Self-recovery and rollback
ota/         # Over-the-air update handling
logging/     # Structured logging (ETW)
tests/       # Unit tests
```

## Security

- Generates Ed25519 keypair on first run, stores private key via Windows DPAPI
- Only trusts commands signed by the Control Plane's public key
- Forwards privileged operations to `quoodle-kernel-guard` via IOCTL — never executes directly
