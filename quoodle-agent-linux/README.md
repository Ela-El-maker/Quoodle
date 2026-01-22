# Quoodle Linux Agent (C++/C Skeleton)

This is a scaffold for implementing the Linux endpoint agent (C++) and privileged executor (C).
It follows the canonical contracts in:
- `docs/specs/WindowsAgent ↔ FastAPI (WSS control channel).json`
- `docs/specs/LinuxAgent ↔ PrivilegedExecutor Interface.json`

Status: **skeleton only** (no real execution logic yet).

## Components
- `agent/`: C++ WSS agent skeleton.
- `privileged/`: C privileged executor skeleton (root-owned).
- `systemd/`: unit files for agent and daemon.

## Build (dev)
```bash
cmake -S . -B build
cmake --build build
```

Dependencies:
- `libsodium` (Ed25519 + base64)
- `pkg-config`
- `cJSON` is vendored for the privileged daemon
- `nlohmann/json` is vendored for the agent (JCS canonicalization)

## Run (dev)
```bash
./build/quoodle-agent-linux
```

```bash
sudo ./build/quoodle-privileged-daemon
```

## Environment
Agent:
- `QUOODLE_WS_URL` (e.g., `wss://gateway.example.com/agent`)
- `QUOODLE_DEVICE_ID`
- `QUOODLE_AGENT_JWT`
- `QUOODLE_AGENT_PRIVKEY_B64`
- `QUOODLE_AGENT_KID`
- `QUOODLE_AGENT_STATE_DIR` (default: `/var/lib/quoodle/agent`)
- `QUOODLE_DAEMON_PUBKEY_B64` (verify daemon responses)

Daemon:
- `QUOODLE_PRIV_SOCKET` (default: `/run/quoodle/privileged.sock`)
- `QUOODLE_DAEMON_PRIVKEY_B64`
- `QUOODLE_DAEMON_KID`
- `QUOODLE_AGENT_PUBKEY_B64` (verify agent requests)
- `QUOODLE_PRIV_STATE_DIR` (default: `/var/lib/quoodle`)
- `QUOODLE_PRIV_ALLOWED_UID` / `QUOODLE_PRIV_ALLOWED_GID` (optional peer-cred allowlist)

## Notes
- Canonicalization must use JCS (RFC 8785).
- The daemon must persist `agent_sequence` and `request_id` dedupe state.
- Unsupported methods must fail closed with `ERR_CAPABILITY_NOT_SUPPORTED`.
