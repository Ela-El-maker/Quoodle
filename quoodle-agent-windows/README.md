# quoodle-agent-windows

Windows endpoint agent. It can run in console mode or as a Windows Service, connects to the gateway over WSS, verifies signatures, and forwards privileged commands to the kernel driver via IOCTL.

## Build

**Prerequisites:** CMake 3.20+, Visual Studio 2022

```bash
mkdir build && cd build
cmake ..
cmake --build . --config Release
```

## Run Modes

Console mode:
```bash
agent.exe --console
```

Service mode (for SCM):
```bash
agent.exe --service
```

Auto-detect mode (default):
- If started by SCM, runs as service.
- Otherwise falls back to console mode.

## Install Service

```powershell
.\scripts\install_agent_service.ps1 -ExePath "C:\path\to\agent.exe"
```

Default service name: `QuoodleAgent`

Optional flags:
- `-DelayedAutoStart`
- `-RestartDelayMs 5000`

Uninstall:
```powershell
.\scripts\uninstall_agent_service.ps1
```

## Background Runtime Guarantee

- The service runs in the background (Session 0) independently of any UI process.
- Closing UI windows does not stop the service.
- Service recovery is configured to auto-restart on failures.
- The service worker loop auto-restarts communicator sessions if the WSS loop exits unexpectedly.

## Device Identity

Persists to `C:/ProgramData/Quoodle/device_id` (auto-generated on first run).

Override order:
- `AGENT_DEVICE_ID`
- `AGENT_DEVICE_ID_FILE`
- default path

## Security

- Verifies signed command envelopes from control plane.
- Forwards privileged operations to `quoodle-kernel-guard` via IOCTL (no direct privileged execution in agent process).
- Driver transport is fail-closed by default when `QUOODLE_USE_KERNEL_DRIVER=1`.
- Explicit pipe fallback is dev/lab only: `QUOODLE_ALLOW_PIPE_FALLBACK=1`.

## Telemetry Runtime Knobs

- `AGENT_HEARTBEAT_INTERVAL_S` (default `30`)
- `AGENT_TELEMETRY_INTERVAL_S` (default `60`)
- `AGENT_TELEMETRY_HTTP_FALLBACK` (default `1`)
- `AGENT_TELEMETRY_FALLBACK_URL` (default `http://localhost:8000`)
- `AGENT_TELEMETRY_QUEUE_DB_PATH` (default `C:/ProgramData/Quoodle/telemetry_queue.db`)
- `AGENT_TELEMETRY_BATCH_SIZE` (default `50`)
- `AGENT_TELEMETRY_MAX_QUEUE_ITEMS` (default `5000`)
- `AGENT_TELEMETRY_RETRY_BACKOFF_S` (default `5`)
- `AGENT_TELEMETRY_RETRY_BACKOFF_MAX_S` (default `300`)

## UI Companion (Milestone 1)

Interactive Windows UI shell lives in `ui-companion/` and is intentionally decoupled from ring0 and backend runtime during this phase.

```powershell
cd ui-companion
dotnet build .\Quoodle.Agent.UiCompanion.csproj -c Release -p:Platform=x64
```

Current provider:
- `MockAgentStateProvider` (local interactive state)
- `UiBridgeProvider` is included as the future seam for named-pipe integration
