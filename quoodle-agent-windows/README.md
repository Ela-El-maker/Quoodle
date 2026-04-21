# quoodle-agent-windows

Windows endpoint runtime for Quoodle.

This component is intentionally service-first:

- `QuoodleAgent` Windows service is the durable runtime.
- UI companion is a bridge client, not a persistence owner.
- Privileged paths are mediated through kernel guard transport.

## 1. Architecture

### 1.1 Process Model

- Service process: networking, auth, dispatch, command execution orchestration.
- Optional UI process: onboarding, telemetry, diagnostics, operator interactions.
- Kernel driver process space: privileged op execution boundary.

### 1.2 Internal Modules

- `src/ws/`: WebSocket client, reconnect strategy, session state.
- `src/command/`: command handlers and dispatch mapping.
- `src/crypto/`: Ed25519 sign/verify, hash helpers.
- `src/control/`: local UI bridge server and status publishing.
- `src/kernel/` and `src/ioctl/`: kernel transport adapters.
- `src/telemetry/`: telemetry queue and upload lifecycle.

### 1.3 Core Runtime Pattern

Pattern: Event-loop orchestrator + state snapshot publishing.

- inbound events: WS messages, timers, service signals.
- derived state: connectivity, auth, pairing, identity, policy.
- outbound events: acks/results, telemetry, local bridge snapshots.

## 2. Design Strategy

### 2.1 Source of Truth Strategy

Service is authoritative for:

- effective device identity
- auth state
- transport state
- command execution state

UI is read-mostly and action-request only.

### 2.2 Identity Reconciliation Strategy

At runtime, identity files and JWT claims are reconciled to reduce stale pairing mismatch.

Inputs:

- `device_id` file
- `agent_jwt` `sub` claim
- bridge-visible effective identity

Goal:

- keep runtime identity coherent before auth and command acceptance.

### 2.3 Fail-Closed Strategy

When signature/auth requirements fail, command execution is denied with explicit failure codes instead of fallback execution.

## 3. Protocols and Contracts

### 3.1 Gateway Session

Endpoint:

- `ws://.../agent` or `wss://.../agent`

Session phases:

1. transport connect
2. authentication
3. command envelope receive
4. ack/progress/result return
5. heartbeat/reconnect loop

### 3.2 Command Verification Contract

Before handler execution:

- validate envelope structure
- validate timestamp/TTL window
- validate device identity targeting
- validate Ed25519 signature against controller pubkey
- validate policy metadata presence

### 3.3 UI Bridge Contract

Named pipe:

- `\\.\pipe\QuoodleAgentUiBridge`

Common operations:

- `status`
- `sync_now`
- `reconnect`
- pairing/status helper operations (depending on build)

Status payload fields include connectivity/auth dimensions, effective identity, and service mode indicators.

### 3.4 Filesystem Discovery Behavior (`list_files`)

- If `path` is omitted/blank, agent defaults discovery scope to `C:\Users`.
- If operators need full-drive traversal, they must set `path` explicitly to `C:\`.
- For explicit `C:\` recursive scans, traversal prioritizes the `Users` branch first, then other top-level directories alphabetically.
- Result bounding still applies (`limit` + `partial=true`) to protect runtime memory and response size.
- Wire contract is unchanged: no new parameters were introduced.

## 4. Build Strategy

Prerequisites:

- Visual Studio C++ toolchain
- Windows SDK
- CMake

Build from `quoodle-agent-windows`:

```powershell
$cmakeCandidates = @("C:\Program Files\CMake\bin\cmake.exe")
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
  $vsRoots = & $vswhere -products * -property installationPath
  foreach ($r in $vsRoots) {
    $cmakeCandidates += (Join-Path $r "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe")
  }
}
$cmakeExe = $cmakeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $cmakeExe) { throw "CMake not found." }

& $cmakeExe -S . -B build --fresh -DUSE_ZLIB=OFF -DIXWEBSOCKET_INSTALL=OFF
& $cmakeExe --build build --config Release --target agent -- /m:1 /v:minimal
```

Output:

- `build\Release\agent.exe`

## 5. Service Operations

Install/reinstall:

```powershell
.\scripts\install_agent_service.ps1 -ExePath "$PWD\build\Release\agent.exe"
```

Control:

```powershell
sc.exe query QuoodleAgent
Restart-Service QuoodleAgent
Stop-Service QuoodleAgent
Start-Service QuoodleAgent
```

Expected configuration:

- auto-start service
- recovery actions configured
- runtime files rooted in `C:\ProgramData\Quoodle`

## 6. Runtime Files

Primary files:

- `C:\ProgramData\Quoodle\device_id`
- `C:\ProgramData\Quoodle\agent_jwt`
- `C:\ProgramData\Quoodle\agent_endpoint`
- `C:\ProgramData\Quoodle\controller_pubkey.b64`
- `C:\ProgramData\Quoodle\agent_pubkey`

These files are part of the operational trust chain. Treat them as sensitive runtime artifacts.

## 7. Security Model

- Command verification is mandatory before execution.
- Controller pubkey parity is required for healthy dispatch.
- Kernel transport can enforce privileged operation boundaries.
- Service identity state should be consistent with pairing outputs.

## 8. Performance and Reliability Techniques

- Exponential reconnect backoff.
- Lightweight runtime status snapshots for UI polling.
- Queue-based telemetry buffering to survive transient network loss.
- Single-instance guard for runtime correctness.

## 9. UI Companion Integration

Build UI companion:

```powershell
$env:DOTNET_CLI_HOME="C:\Users\felix\Work-Force\Quoodle\.dotnet_cli_home"
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1"
dotnet build -c Release .\ui-companion\Quoodle.Agent.UiCompanion.csproj
```

Launch:

```powershell
Start-Process ".\ui-companion\bin\Release\net8.0-windows10.0.26100.0\Quoodle.Agent.UiCompanion.exe"
```

## 10. Troubleshooting Matrix

### Service Running but Device Offline

Check:

1. pipe status `connected/authenticated` fields
2. endpoint scheme and reachability
3. `agent_jwt` validity and `device_id` match
4. gateway logs for auth errors

### Signature Invalid

Check:

1. `controller_pubkey.b64` equals gateway signing key endpoint
2. stale env overrides (for example old expected pubkey vars)
3. service restart after key updates

### Commands Stuck Queued

Check:

1. gateway sees active channel for device
2. control-plane dispatch job success
3. agent auth state in bridge status

### UI Shows Stale Enrollment

Check:

1. runtime identity files under `C:\ProgramData\Quoodle`
2. pairing session completion in control plane
3. bridge status transition to authenticated session

## 11. Sequence Diagrams

### 11.1 Service Startup and Connect Loop

```text
SCM               QuoodleAgent Service       Gateway WS
 |                         |                     |
 | start service           |                     |
 |------------------------>| load runtime files  |
 |                         | open UI bridge pipe |
 |                         | connect endpoint    |
 |                         |-------------------->|
 |                         | auth + heartbeat    |
 |                         |<------------------->|
```

### 11.2 Signed Command Execution Path

```text
Gateway WS          Agent Verifier         Handler Router        Kernel Guard
    |                    |                      |                    |
    | envelope           | verify sig/ttl       |                    |
    |------------------->|--------------------->| select handler     |
    |                    |                      |----IOCTL if needed->|
    |                    |                      |<---result-----------|
    | result/failed      |                      |                    |
    |<-------------------|                      |                    |
```
