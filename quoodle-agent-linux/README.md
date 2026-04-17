# quoodle-agent-linux

Linux endpoint runtime for Quoodle.

Components:

- unprivileged agent process (networking, signatures, command orchestration)
- privileged daemon (root boundary for protected operations)
- CLI and optional local UI utilities

## 1. Responsibilities

Agent responsibilities:

- connect/authenticate to gateway
- verify command signatures
- execute non-privileged handlers
- forward privileged requests to daemon over UDS
- return structured results and telemetry

Privileged daemon responsibilities:

- enforce root-only operations
- validate caller trust boundary
- return signed or integrity-checked execution receipts

## 2. Build

Prerequisites:

- CMake
- C++17 compiler
- libsodium
- pkg-config

Build:

```bash
cmake -S . -B build
cmake --build build
```

Run binaries:

```bash
./build/quoodle-agent-linux
sudo ./build/quoodle-privileged-daemon
```

## 3. CLI Utilities

```bash
./cli/quoodle-agent status
./cli/quoodle-agent doctor
./cli/quoodle-agent logs --follow
./cli/quoodle-agent attest
./cli/quoodle-agent pair --api-base http://localhost:8088 --user-jwt "$USER_JWT" --update-secrets
```

## 4. Local UI Utilities

```bash
./ui/quoodle-agent-ui --desktop
./ui/quoodle-agent-ui --tui
./ui/quoodle-agent-ui --tray
```

## 5. Service Mode (systemd)

```bash
sudo systemctl enable --now quoodle-agent quoodle-privileged
```

Optional user-session UI auto-start:

```bash
./ui/install_user_service.sh
systemctl --user enable --now quoodle-agent-ui.service
```

## 6. Environment Variables

Agent:

- `QUOODLE_WS_URL`
- `QUOODLE_AGENT_JWT`
- `QUOODLE_AGENT_PRIVKEY_B64`
- `QUOODLE_CONTROLLER_PUBKEY_B64`
- `QUOODLE_DAEMON_PUBKEY_B64`
- `QUOODLE_DEVICE_ID`

Daemon:

- `QUOODLE_PRIV_SOCKET`
- `QUOODLE_DAEMON_PRIVKEY_B64`
- `QUOODLE_AGENT_PUBKEY_B64`

## 7. Project Layout

- `agent/` core Linux agent
- `privileged/` privileged daemon
- `cli/` operator/debug CLI
- `ui/` desktop/tui/tray tools
- `systemd/` service units
- `systemd-user/` user service units

## 8. Troubleshooting

- cannot execute privileged command: verify daemon running and socket permissions
- signature invalid: verify controller public key and signing chain
- no telemetry: verify gateway reachability and auth token validity
- duplicate identity: verify device ID persistence path and overrides
