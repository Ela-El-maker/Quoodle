# quoodle-agent-windows/ui-companion

WinUI 3 local companion for the Windows agent runtime.

The UI is intentionally a thin, stateful observer over a service-owned runtime.

## 1. Architecture

### 1.1 Pattern

- Presentation: WinUI views and controls.
- State orchestration: ViewModels and state mappers.
- Runtime integration: `IAgentStateProvider` implementations.
- Transport: named pipe + SCM status + runtime files.

Primary pattern set:

- MVVM for presentation isolation.
- Adapter pattern for bridge providers.
- Snapshot-diff update pattern to avoid noisy redraw.

### 1.2 Source Inputs

- SCM (`QuoodleAgent`) state.
- Named pipe status payload (`QuoodleAgentUiBridge`).
- Runtime identity artifacts under `C:\ProgramData\Quoodle`.

### 1.3 Output Responsibilities

- accurate onboarding state machine rendering
- service/runtime health visibility
- operator-safe actions (`sync_now`, reconnect, pairing helpers)

## 2. UI State Machines

### 2.1 Onboarding

- Detect
- Pair
- Confirm
- Complete

Important rule:

- completion state should represent authenticated runtime reality, not stale local file presence.

### 2.2 Runtime Health

- connected/authenticated
- reconnecting/degraded
- disconnected/offline

Health cards should map from bridge-reported runtime fields, not only SCM process state.

## 3. Runtime Bridge Contract

Provider:

- `UiBridgeProvider`

Pipe path:

- `\\.\pipe\QuoodleAgentUiBridge`

Common operations:

- `status`
- `sync_now`
- `reconnect`

Representative `status` dimensions:

- `connected`
- `authenticated`
- `auth_state`
- `connection_state`
- `device_id`
- `effective_device_id`
- `endpoint`
- `communicator_present`
- `service_mode`

## 4. Bootstrap and Recovery Strategy

At startup:

1. verify service install state
2. start service if stopped
3. wait for bridge readiness window
4. begin polling/subscription
5. reconcile UI state from latest snapshot

Recovery behaviors:

- transient bridge failure triggers retry, not fatal crash
- stale pairing views are resettable from UI action
- change detection avoids over-render and reduces UI jitter

## 5. Build and Run

From `quoodle-agent-windows`:

```powershell
$env:DOTNET_CLI_HOME="C:\Users\felix\Work-Force\Quoodle\.dotnet_cli_home"
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1"
dotnet build -c Release .\ui-companion\Quoodle.Agent.UiCompanion.csproj
```

Run:

```powershell
Start-Process ".\ui-companion\bin\Release\net8.0-windows10.0.26100.0\Quoodle.Agent.UiCompanion.exe"
```

## 6. Development Design Guidelines

- Keep service lifecycle logic out of views.
- Keep bridge schema changes backward compatible when possible.
- Prefer adding ViewModel fields over view-local business logic.
- Preserve existing visual language unless explicitly redesigning.

## 7. Optional Mock Mode

```powershell
$env:QUOODLE_UI_USE_MOCK = "1"
```

Use only for UI-only iteration where runtime coupling is intentionally disabled.

## 8. Testing

```powershell
dotnet test .\ui-companion\tests\Quoodle.Agent.UiCompanion.Tests\Quoodle.Agent.UiCompanion.Tests.csproj
```

Recommended coverage areas:

- onboarding transitions
- bridge parse and null-safety behavior
- stale-state reset behavior
- role/visibility guards for UI surfaces

## 9. Troubleshooting

### UI Says Offline but Service Is Running

- SCM running only proves process liveness.
- Verify bridge `connected` and `authenticated` fields.
- Validate endpoint and JWT/device identity coherence.

### Pairing Appears Stuck

- verify control-plane pair session progress
- verify runtime bridge status refresh
- use reset pair action when local stale state is suspected

### Rebuild Errors

- close running UI process before build
- ensure correct project path: `.\ui-companion\Quoodle.Agent.UiCompanion.csproj`

## 10. Sequence Diagrams

### 10.1 UI Bootstrap to Live Status

```text
UI App             SCM                Agent Service          Named Pipe
  |                 |                     |                     |
  | launch          |                     |                     |
  |---------------->| query status        |                     |
  |                 | start if stopped    |                     |
  |                 |-------------------->| init bridge         |
  | connect bridge  |                     |                     |
  |----------------------------------------------------------->|
  | status poll     |                     |<--------------------|
  | render health   |                     |                     |
```

### 10.2 Onboarding Progress Gate

```text
UI Onboarding        Bridge Status         Runtime Auth State
     |                    |                       |
     | Detect complete    |                       |
     | Pair token submit  |---------------------->|
     | wait confirm       | connected+authenticated?
     |<-------------------| yes -> Confirm complete
```
