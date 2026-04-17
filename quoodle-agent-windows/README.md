# quoodle-agent-windows

Windows endpoint runtime for Quoodle.

It is a service-first architecture:

- background service (`QuoodleAgent`) is the durable runtime
- UI companion is a local observer/controller over named pipe
- privileged execution is brokered through kernel guard IOCTL path

## 1. Responsibilities

Service responsibilities:

- authenticate to gateway and maintain session
- verify command signatures
- execute command handlers and privileged dispatches
- persist runtime identity artifacts under `C:\ProgramData\Quoodle`
- expose local UI bridge at `\\.\pipe\QuoodleAgentUiBridge`

UI companion responsibilities:

- display runtime onboarding, health, telemetry, and command state
- trigger sync/reconnect/pairing-related actions through bridge ops
- never own persistence or enforcement lifecycle

## 2. Build

Prerequisites:

- Visual Studio 2022 C++ toolchain + Windows SDK
- CMake 3.20+

From `quoodle-agent-windows`:

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

Binary output:

- `build\Release\agent.exe`

## 3. Run Modes

Console diagnostics:

```powershell
.\build\Release\agent.exe --console
```

Service mode:

```powershell
.\build\Release\agent.exe --service
```

Do not run console mode while service mode is active; single-instance guard will reject duplicate process.

## 4. Install and Manage Service

Install/reinstall:

```powershell
.\scripts\install_agent_service.ps1 -ExePath "$PWD\build\Release\agent.exe"
```

Status:

```powershell
sc.exe query QuoodleAgent
```

The installer configures:

- startup type
- recovery actions
- controller pubkey file path
- service env defaults for kernel driver path

## 5. Runtime Files and Identity

Primary runtime files:

- `C:\ProgramData\Quoodle\device_id`
- `C:\ProgramData\Quoodle\agent_jwt`
- `C:\ProgramData\Quoodle\agent_endpoint`
- `C:\ProgramData\Quoodle\controller_pubkey.b64`
- `C:\ProgramData\Quoodle\agent_pubkey`

Identity source order:

1. env override
2. persisted runtime file
3. generated bootstrap placeholder when unpaired

## 6. Pairing and Enrollment

- unpaired service can still start and expose bridge
- pairing token/QR flow provisions device identity and JWT
- ownership confirm in control UI binds device to user
- service reconnect applies new credentials

## 7. Security Notes

- command signatures are verified locally
- controller pubkey must match gateway signer
- kernel-driver transport is default path (`QUOODLE_USE_KERNEL_DRIVER=1`)
- pipe fallback is lab-only behavior

## 8. UI Companion

Build UI companion:

```powershell
$env:DOTNET_CLI_HOME="C:\Users\felix\Work-Force\Quoodle\.dotnet_cli_home"
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1"
dotnet build -c Release .\ui-companion\Quoodle.Agent.UiCompanion.csproj
```

Launch UI:

```powershell
Start-Process ".\ui-companion\bin\Release\net8.0-windows10.0.26100.0\Quoodle.Agent.UiCompanion.exe"
```

UI startup behavior:

- checks service install state
- starts service if stopped
- waits for pipe bridge readiness
- attaches to live runtime state

## 9. Troubleshooting

Service running but offline in UI/control plane:

1. `sc.exe query QuoodleAgent`
2. probe `QuoodleAgentUiBridge` status payload
3. verify `agent_jwt`, `device_id`, endpoint values
4. verify gateway signing key parity with local `controller_pubkey.b64`

Commands stuck queued:

- validate `authenticated=true` in pipe status
- verify gateway logs show device channel online

Signature invalid:

- compare local `controller_pubkey.b64` with `GET /api/v1/controller/signing-key`
- restart service after key refresh
