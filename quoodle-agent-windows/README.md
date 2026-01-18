# 💻 quoodle-agent-windows

**Role**: Execution / Enforcement (User Mode)
**Tech Stack**: C++ (WinAPI, Boost.Asio)
**Responsibility**: WSS Client, Command Verification, Telemetry Producer.

---

## 📖 Overview

The `quoodle-agent-windows` is the user-mode persistent service running on the target device. It is reliable for:

1.  **Transport**: Establishing the mTLS-secured WebSocket to `quoodle-gateway`.
2.  **Verification**: Verifying Ed25519 signatures on all incoming command envelopes.
3.  **Kernel Bridge**: Forwarding validated commands to `quoodle-kernel-guard` via IOCTL.
4.  **Telemetry**: Collecting system metrics and streaming them upstream.

## 🛠️ Build & Run

### Prerequisites
- CMake 3.20+
- Visual Studio 2022 (MSVC)
- Boost Libraries
- OpenSSL

### Setup

```bash
mkdir build
cd build
cmake ..
cmake --build . --config Release
```

### Running

```bash
./quoodle-agent-windows.exe --config config.json
```

## 🔐 Security Context

- **Keys**: Generates a unique Ed25519 keypair on first run. Stores private key in Windows DPAPI.
- **Trust**: Only trusts commands signed by the Control Plane's public key (hardcoded or pinned).
