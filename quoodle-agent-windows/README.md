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

## Pairing Bootstrap Mode

- If `AGENT_JWT` is missing, the agent now starts in discovery mode and still sends AUTH to gateway/control-plane.
- Unknown devices are surfaced as pending pairing (`pending_pairing`) until pairing completes.
- Once pairing succeeds and `agent_jwt` is written, subsequent AUTH uses the paired credentials automatically.

## Agent Signing Key Bootstrap

Ed25519 private key lookup order:

1. `ED25519_PRIVATE_KEY_B64`
2. DPAPI vars (`ED25519_PRIVATE_KEY_DPAPI_B64` / `ED25519_PRIVATE_KEY_DPAPI_PATH`)
3. File path `ED25519_PRIVATE_KEY_PATH` (default `C:/ProgramData/Quoodle/ed25519_private_key.b64`)

If no key exists and the agent is unpaired (no `AGENT_JWT`), a local key is auto-generated and persisted to the default file path.

Disable auto-generation:

```powershell
$env:ED25519_AUTOGEN_PRIVATE_KEY = "0"
```

## Security

- Verifies signed command envelopes from control plane.
- Forwards privileged operations to `quoodle-kernel-guard` via IOCTL (no direct privileged execution in agent process).
- Driver transport is enabled by default (fail-closed when driver is unavailable).
- Explicitly disable driver mode only for lab/dev with `QUOODLE_USE_KERNEL_DRIVER=0`.
- Explicit pipe fallback is dev/lab only: `QUOODLE_ALLOW_PIPE_FALLBACK=1`.
- Command signature verification requires controller public key (`CONTROLLER_PUBKEY_B64` or `CONTROLLER_PUBKEY_PATH`).

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
- `UiBridgeProvider` uses local named-pipe integration for runtime status/actions

UI bridge runtime pipe (local machine only):

- `\\.\pipe\QuoodleAgentUiBridge`
- Ops: `status`, `sync_now`, `reconnect`

Start with this order so pairing works cleanly.

**1) Bring up backend + web UI**
Use your repo root `c:\Users\felix\Work-Force\Quoodle`:

```powershell
docker compose up -d --build control-plane gateway control-plane-ui
```

Open:

- Control UI: `http://localhost:3000`
- Control API: `http://localhost:8088`
- Gateway health: `http://localhost:8000/health`

**2) Build Windows agent runtime (C++)**

```powershell
cd quoodle-agent-windows
mkdir build
cd build
cmake ..
cmake --build . --config Release --target agent
```

If needed, install/start service:

```powershell
# from quoodle-agent-windows
.\scripts\install_agent_service.ps1 -ExePath "C:\Users\felix\Work-Force\Quoodle\quoodle-agent-windows\build\Release\agent.exe"
Start-Service QuoodleAgent
```

**3) Build + run UI companion**

```powershell
cd c:\Users\felix\Work-Force\Quoodle\quoodle-agent-windows\ui-companion
dotnet build .\Quoodle.Agent.UiCompanion.csproj -c Release -p:Platform=x64
```

Then launch the generated UI exe from `bin\Release\...`.

**4) Run mobile app**

```bash
cd quoodle-mobile-client
flutter pub get
flutter run --dart-define=QDO_CONTROL_PLANE_BASE_URL=http://<YOUR_PC_IP>:8088/api
```

- Physical phone: use your PC LAN IP, not `localhost`.
- Emulator: use emulator loopback rules if needed (`10.0.2.2` on Android emulator).

**5) Pairing flow (new)**

1. In Control UI, open Pair Device and generate 6-digit code.  
2. In Windows agent UI (Token tab), enter that 6-digit code.  
3. In Control UI, confirm detected device details.  
4. Optionally, use QR tab in Windows UI and scan from mobile app; mobile now confirms via `/pair/confirm`.
