# Quoodle Local Installation and End-to-End Runbook

This guide is the canonical local setup flow for running Quoodle end-to-end on a Windows host:

- control plane UI (`localhost:3000`)
- control plane API (`localhost:8088`)
- gateway (`localhost:8000`)
- Windows agent service (`QuoodleAgent`)
- Windows UI companion
- optional mobile client pairing and command path

Use this when you want a clean, repeatable "zero-to-hero" manual run without wrapper scripts.

## 1. Prerequisites

Install these first:

- Docker Desktop (with Compose)
- PowerShell 7 or Windows PowerShell (Admin terminal required for service install)
- Visual Studio 2022 C++ tools (or Build Tools) with MSVC + Windows SDK
- CMake (or VS-bundled CMake)
- .NET SDK 8+ for UI companion
- Flutter SDK (only if you want mobile testing)

Repository root used in examples:

`C:\Users\felix\Work-Force\Quoodle`

## 2. One-Time Repo Setup

From repo root:

```powershell
cd C:\Users\felix\Work-Force\Quoodle
Copy-Item .env.example .env -Force
```

## 3. Start Backend Stack

From repo root:

```powershell
docker compose --env-file .env up -d --build
docker compose ps
```

Expected endpoints:

- Control UI: `http://localhost:3000`
- Control API: `http://localhost:8088`
- Gateway: `http://localhost:8000`
- Gateway health: `http://localhost:8000/health`

## 4. Build Windows Agent (C++)

Open an **Admin PowerShell**:

```powershell
cd C:\Users\felix\Work-Force\Quoodle\quoodle-agent-windows
```

Resolve CMake path (works with standalone CMake or VS-bundled CMake):

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
if (-not $cmakeExe) { throw "CMake not found. Install CMake or VS CMake tools." }
& $cmakeExe --version
```

Configure and build:

```powershell
& $cmakeExe -S . -B build --fresh -DUSE_ZLIB=OFF -DIXWEBSOCKET_INSTALL=OFF
& $cmakeExe --build build --config Release --target agent -- /m:1 /v:minimal
```

Output binary:

`quoodle-agent-windows\build\Release\agent.exe`

## 5. Install and Start Agent Service

Still in Admin PowerShell:

```powershell
cd C:\Users\felix\Work-Force\Quoodle\quoodle-agent-windows
.\scripts\install_agent_service.ps1 -ExePath "$PWD\build\Release\agent.exe"
sc.exe query QuoodleAgent
```

Expected:

- service exists
- state is `RUNNING`

## 6. Verify Runtime Identity and Bridge

Confirm local runtime files:

```powershell
Get-Content C:\ProgramData\Quoodle\device_id
Get-Content C:\ProgramData\Quoodle\agent_endpoint
Get-Content C:\ProgramData\Quoodle\agent_jwt
```

Probe UI bridge pipe:

```powershell
$pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'QuoodleAgentUiBridge', [System.IO.Pipes.PipeDirection]::InOut)
$pipe.Connect(2000)
$sw = New-Object System.IO.StreamWriter($pipe); $sw.AutoFlush = $true
$sr = New-Object System.IO.StreamReader($pipe)
$sw.WriteLine('{"op":"status"}')
$sr.ReadLine()
```

Healthy status should eventually show:

- `communicator_present=true`
- `connected=true`
- `authenticated=true`

## 7. Build and Run UI Companion

From `quoodle-agent-windows`:

```powershell
$env:DOTNET_CLI_HOME="C:\Users\felix\Work-Force\Quoodle\.dotnet_cli_home"
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1"
dotnet build -c Release .\ui-companion\Quoodle.Agent.UiCompanion.csproj
```

Run UI:

```powershell
Start-Process ".\ui-companion\bin\Release\net8.0-windows10.0.26100.0\Quoodle.Agent.UiCompanion.exe"
```

Notes:

- UI is service-first: it attempts best-effort service bootstrap, then attaches to `\\.\pipe\QuoodleAgentUiBridge`.
- Closing UI does not stop service.

## 8. Pairing Flow (Control UI + Agent UI)

1. Open `http://localhost:3000` and sign in.
2. Open Pair Device and generate pairing code.
3. In Agent UI onboarding, enter 6-digit code (or scan QR with mobile app).
4. Confirm ownership in Control UI (device name + last 6 of device ID).
5. Verify device appears in device management.

Expected:

- Agent UI transitions Detect -> Pair -> Confirm.
- Device is visible as claimed in control plane.
- Status becomes online once authenticated WSS connection is active.

## 9. Optional Mobile App Setup

From `quoodle-mobile-client`:

```powershell
flutter clean
flutter pub get
flutter run
```

For physical phone, use LAN IP for control API base URL (not `localhost`).

## 10. End-to-End Command Test

From control UI, send:

- `collect_system_info`
- `list_processes`

Expected:

- command trace progresses through all stages
- result status becomes `completed`
- no lingering `queued` with reason `device not connected`

## 11. Troubleshooting

### 11.1 Service running but device offline

Check:

```powershell
sc.exe query QuoodleAgent
```

Then inspect pipe runtime status (Section 6). If `connected=false` or `authenticated=false`, inspect gateway connectivity and JWT/device identity.

### 11.2 Commands stuck queued

Typical cause: runtime not authenticated to gateway.

Check:

- `C:\ProgramData\Quoodle\agent_jwt` exists and matches current paired device
- pipe status reports authenticated
- gateway logs show agent auth/connect activity

### 11.3 Signature invalid

Confirm controller key file matches live gateway key:

```powershell
(Get-Content "C:\ProgramData\Quoodle\controller_pubkey.b64" -Raw).Trim()
(Invoke-RestMethod "http://localhost:8000/api/v1/controller/signing-key").controller_pubkey_b64
```

Then restart service:

```powershell
Restart-Service QuoodleAgent
```

### 11.4 UI shows stale onboarding/session

Use Agent UI "Reset Pair" flow (if exposed), or clear local runtime pairing artifacts and re-pair:

```powershell
Stop-Service QuoodleAgent
Remove-Item C:\ProgramData\Quoodle\agent_jwt -ErrorAction SilentlyContinue
Remove-Item C:\ProgramData\Quoodle\device_id -ErrorAction SilentlyContinue
Start-Service QuoodleAgent
```

## 12. Clean Local Reset (Development)

Warning: this removes local state and container data.

```powershell
cd C:\Users\felix\Work-Force\Quoodle
docker compose --env-file .env down -v
```

Then clear agent runtime files (Admin PowerShell):

```powershell
Stop-Service QuoodleAgent -ErrorAction SilentlyContinue
Get-Process agent -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item C:\ProgramData\Quoodle\agent_jwt -ErrorAction SilentlyContinue
Remove-Item C:\ProgramData\Quoodle\device_id -ErrorAction SilentlyContinue
Remove-Item C:\ProgramData\Quoodle\controller_pubkey.b64 -ErrorAction SilentlyContinue
```

Restart from Section 3.

## 13. Operational Notes

- Service persistence comes from SCM + kernel-assisted architecture, not the UI process.
- UI is an observer/controller over local pipe bridge.
- Do not run `agent.exe --console` while service is running; single-instance guard will reject duplicate process.
- Keep production usage on service mode; console mode is for diagnostics.
