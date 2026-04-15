# Quoodle Agent UI Companion

WinUI 3 (.NET 8) local interactive UI shell for Windows Agent.

## Milestone 1 Scope
- Onboarding, Dashboard, Quick Status, Activity/Diagnostics, Settings
- Local state provider (`MockAgentStateProvider`) for onboarding/settings simulation
- Live runtime bridge (`UiBridgeProvider`) for service status + device identity

## Live Bridge Mode

The UI now defaults to `UiBridgeProvider` and reads live local runtime state from:
- Windows service status for `QuoodleAgent`
- Device identity at `C:\ProgramData\Quoodle\device_id`
- Agent runtime pipe RPC at `\\.\pipe\QuoodleAgentUiBridge` (`status`, `sync_now`, `reconnect`)

To force classic mock-only behavior:

```powershell
$env:QUOODLE_UI_USE_MOCK = "1"
```

## Milestone 1.5 Additions
- Device Details, Command History, Pairing Recovery (top-level navigation)
- Shared snapshot extensions for `DeviceFacts` and `CommandHistory`
- Recovery actions: retry connection, start re-pair flow, reset UI session

## Run
```powershell
dotnet build .\Quoodle.Agent.UiCompanion.csproj -c Release -p:Platform=x64
```

## Dashboard VM Tests
```powershell
dotnet test .\tests\Quoodle.Agent.UiCompanion.Tests\Quoodle.Agent.UiCompanion.Tests.csproj
```
