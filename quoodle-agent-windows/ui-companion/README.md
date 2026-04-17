# quoodle-agent-windows/ui-companion

WinUI 3 local companion for the Windows agent runtime.

This UI is service-first and bridge-driven.

## 1. What This UI Does

- onboarding detect/pair/confirm workflow
- live runtime dashboard and quick status
- activity and diagnostics visibility
- settings and transport controls
- pairing recovery/reset actions

## 2. What This UI Does Not Do

- it does not own agent persistence
- it does not replace the Windows service lifecycle
- it does not execute privileged actions directly

## 3. Runtime Bridge Contract

Provider:

- `UiBridgeProvider`

Sources:

- SCM service state for `QuoodleAgent`
- runtime file state under `C:\ProgramData\Quoodle`
- named pipe RPC `\\.\pipe\QuoodleAgentUiBridge`

Pipe operations:

- `status`
- `sync_now`
- `reconnect`

## 4. Startup Bootstrap Behavior

On launch the bridge performs best-effort bootstrap:

1. check whether `QuoodleAgent` exists
2. start service when installed but stopped
3. wait briefly for pipe readiness
4. start continuous runtime polling

Closing UI does not stop service.

## 5. Build

From `quoodle-agent-windows`:

```powershell
$env:DOTNET_CLI_HOME="C:\Users\felix\Work-Force\Quoodle\.dotnet_cli_home"
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1"
dotnet build -c Release .\ui-companion\Quoodle.Agent.UiCompanion.csproj
```

## 6. Run

```powershell
Start-Process ".\ui-companion\bin\Release\net8.0-windows10.0.26100.0\Quoodle.Agent.UiCompanion.exe"
```

## 7. Optional Mock Mode

```powershell
$env:QUOODLE_UI_USE_MOCK = "1"
```

Use mock mode only for isolated UI development.

## 8. Tests

```powershell
dotnet test .\ui-companion\tests\Quoodle.Agent.UiCompanion.Tests\Quoodle.Agent.UiCompanion.Tests.csproj
```

## 9. Troubleshooting

- stale onboarding state: use reset pair flow and verify runtime files
- service shows running but UI offline: inspect pipe `status` payload
- pairing confirm hangs: verify control plane pair session status and bridge auth state
- build copy errors: close running UI process before rebuilding
