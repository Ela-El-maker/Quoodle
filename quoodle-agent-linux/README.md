# quoodle-agent-linux

Linux endpoint agent with a privileged daemon for secure command execution. Connects to the gateway over WSS, verifies Ed25519 signatures, and delegates OS actions to an isolated root daemon via Unix Domain Socket.

**Stack:** C++17 / C / Python

## Build & Run

**Prerequisites:** CMake, C++17 compiler, `libsodium`, `pkg-config`

```bash
cmake -S . -B build
cmake --build build

# Run the agent (unprivileged)
./build/quoodle-agent-linux

# Run the privileged daemon (root)
sudo ./build/quoodle-privileged-daemon
```

## CLI

```bash
./cli/quoodle-agent status          # Agent status
./cli/quoodle-agent doctor          # Diagnostics
./cli/quoodle-agent logs --follow   # Live logs
./cli/quoodle-agent attest          # Attestation report
./cli/quoodle-agent pair \          # Pair without QR
  --api-base http://localhost:8080 \
  --user-jwt "$USER_JWT" --update-secrets
```

## UI

```bash
./ui/quoodle-agent-ui --desktop     # Tkinter desktop UI
./ui/quoodle-agent-ui --tui         # Terminal UI (curses)
./ui/quoodle-agent-ui --tray        # System tray (pystray + pillow)
```

## Systemd

```bash
# Install and enable system services
sudo systemctl enable --now quoodle-agent quoodle-privileged

# User-level UI auto-start
./ui/install_user_service.sh
systemctl --user enable --now quoodle-agent-ui.service
```

## Environment Variables

**Agent:**

| Variable | Description |
|---|---|
| `QUOODLE_WS_URL` | Gateway WebSocket URL |
| `QUOODLE_AGENT_JWT` | Agent authentication token |
| `QUOODLE_AGENT_PRIVKEY_B64` | Agent Ed25519 private key (base64) |
| `QUOODLE_CONTROLLER_PUBKEY_B64` | Controller public key for signature verification |
| `QUOODLE_DAEMON_PUBKEY_B64` | Daemon public key for response verification |
| `QUOODLE_DEVICE_ID` | Override device ID (default: `/var/lib/quoodle/device_id`) |

**Daemon:**

| Variable | Description |
|---|---|
| `QUOODLE_PRIV_SOCKET` | UDS path (default: `/run/quoodle/privileged.sock`) |
| `QUOODLE_DAEMON_PRIVKEY_B64` | Daemon Ed25519 private key (base64) |
| `QUOODLE_AGENT_PUBKEY_B64` | Agent public key for request verification |

## Project Structure

```
agent/       # C++ WSS agent (Ed25519, command execution, telemetry)
privileged/  # C privileged daemon (root, UDS IPC, policy enforcement)
cli/         # Python CLI tool
ui/          # Desktop/TUI/tray interfaces
systemd/     # System service unit files
systemd-user/# User service unit files
```
