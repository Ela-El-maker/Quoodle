# Quoodle Agent UI Companion

WinUI 3 (.NET 8) local interactive UI shell for Windows Agent.

## Milestone 1 Scope
- Onboarding, Dashboard, Quick Status, Activity/Diagnostics, Settings
- Mock-only state provider (`MockAgentStateProvider`)
- Explicit seam for future live bridge (`UiBridgeProvider`)

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
