# quoodle-agent-linux

Linux endpoint runtime for Quoodle.

Design mirrors Windows service-first intent, with a strict unprivileged/privileged split.

## 1. Architecture

### 1.1 Process Topology

- Unprivileged agent process: gateway transport, command verification, handler orchestration.
- Privileged daemon: root-bound operations behind controlled IPC.
- Optional local UI and CLI tools: diagnostics and operator support.

### 1.2 Trust Boundary

Primary local trust boundary is the Unix domain socket interface between agent and privileged daemon.

Agent must prove caller legitimacy and operation intent; daemon enforces capability constraints.

## 2. Stack and Why

- C++17 for agent runtime logic and predictable system integration.
- C in privileged path where minimal low-level control is preferred.
- Python helpers for operational ergonomics and tooling.

## 3. Command and Verification Pipeline

For each inbound envelope:

1. parse envelope and validate schema
2. validate TTL/timestamp and target identity
3. verify Ed25519 signature against controller key
4. route to local handler or privileged daemon request
5. normalize and emit result

## 4. Privileged Execution Strategy

Privileged daemon responsibilities:

- accept only known opcodes/requests
- enforce argument bounds and policy checks
- return structured results
- avoid exposing generic shell-level primitives

## 5. Build

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

## 6. Service Mode (systemd)

```bash
sudo systemctl enable --now quoodle-agent quoodle-privileged
```

Optional user-session UI service:

```bash
./ui/install_user_service.sh
systemctl --user enable --now quoodle-agent-ui.service
```

## 7. CLI and Local UI Utilities

CLI:

```bash
./cli/quoodle-agent status
./cli/quoodle-agent doctor
./cli/quoodle-agent logs --follow
./cli/quoodle-agent attest
./cli/quoodle-agent pair --api-base http://localhost:8088 --user-jwt "$USER_JWT" --update-secrets
```

UI:

```bash
./ui/quoodle-agent-ui --desktop
./ui/quoodle-agent-ui --tui
./ui/quoodle-agent-ui --tray
```

## 8. Environment Contract

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

## 9. Project Layout

- `agent/`: main runtime
- `privileged/`: privileged boundary implementation
- `cli/`: command-line operational tools
- `ui/`: desktop/tui/tray companion
- `systemd/`: system units
- `systemd-user/`: user units

## 10. Troubleshooting

### Privileged Requests Failing

- verify daemon process is running
- verify socket path and permissions
- verify agent and daemon key parity

### Signature Invalid

- verify controller pubkey consistency with gateway/control-plane signer
- verify no stale key overrides in environment

### Device Offline

- verify websocket endpoint reachability
- verify agent JWT validity and device identity coherence

## 11. Sequence Diagrams

### 11.1 Linux Command Handling with Privileged Split

```text
Gateway WS         Linux Agent           Privileged Daemon         OS Resource
    |                  |                        |                      |
    | envelope         | verify+route           |                      |
    |----------------->|----------------------->| root op request      |
    |                  |                        |--------------------->|
    |                  |                        |<---------------------|
    | result           | normalize result       |                      |
    |<-----------------|                        |                      |
```

### 11.2 Systemd Recovery Loop

```text
systemd           quoodle-agent          quoodle-privileged
   |                   |                        |
   | start units       |                        |
   |------------------>|                        |
   |------------------>|----------------------->|
   | crash detected    |                        |
   | restart policy -->|                        |
```
