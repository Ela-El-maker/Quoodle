param(
    [string]$DriverPath = "$PSScriptRoot\..\driver\kmdf\x64\Release\quoodle_kmdf.sys",
    [string]$ServiceName = "QuoodleKernel",
    [string]$HmacKey = $env:QUOODLE_DRIVER_HMAC_KEY,
    [switch]$TestSigning,
    [switch]$NoStart
)

$ErrorActionPreference = "Stop"

function Assert-AdminContext {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script in an elevated PowerShell session (Administrator)."
    }
}

function Resolve-DriverPath {
    param([string]$PreferredPath)

    $candidates = @(
        $PreferredPath,
        "$PSScriptRoot\..\driver\kmdf\quoodle_kmdf\x64\Release\quoodle_kmdf.sys"
    )

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $resolved = [System.IO.Path]::GetFullPath($candidate)
        if (Test-Path $resolved) {
            return $resolved
        }
    }

    return $null
}

function Wait-ServiceRunning {
    param(
        [string]$Name,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Wait-ServiceDeleted {
    param(
        [string]$Name,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        & sc.exe query $Name *> $null
        if ($LASTEXITCODE -eq 1060) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Ensure-NativeDeviceApi {
    if (([System.Management.Automation.PSTypeName]'Quoodle.NativeDeviceApi').Type) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Quoodle {
    public static class NativeDeviceApi {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern SafeFileHandle CreateFile(
            string lpFileName,
            uint dwDesiredAccess,
            uint dwShareMode,
            IntPtr lpSecurityAttributes,
            uint dwCreationDisposition,
            uint dwFlagsAndAttributes,
            IntPtr hTemplateFile
        );
    }
}
"@
}

function Get-Win32Message {
    param([int]$Code)

    if ($Code -eq 0) {
        return "SUCCESS"
    }

    return (New-Object System.ComponentModel.Win32Exception($Code)).Message
}

function Try-OpenDevicePath {
    param(
        [Parameter(Mandatory = $true)][string]$DevicePath,
        [Parameter(Mandatory = $true)][uint32]$DesiredAccess,
        [Parameter(Mandatory = $true)][string]$AccessLabel
    )

    Ensure-NativeDeviceApi

    $handle = [Quoodle.NativeDeviceApi]::CreateFile(
        $DevicePath,
        $DesiredAccess,
        3,     # FILE_SHARE_READ | FILE_SHARE_WRITE
        [IntPtr]::Zero,
        3,     # OPEN_EXISTING
        0x80,  # FILE_ATTRIBUTE_NORMAL
        [IntPtr]::Zero
    )

    if (-not $handle.IsInvalid) {
        $handle.Dispose()
        return [pscustomobject]@{
            Path = $DevicePath
            Access = $AccessLabel
            Success = $true
            ErrorCode = 0
            ErrorMessage = "SUCCESS"
        }
    }

    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $handle.Dispose()
    return [pscustomobject]@{
        Path = $DevicePath
        Access = $AccessLabel
        Success = $false
        ErrorCode = $err
        ErrorMessage = (Get-Win32Message -Code $err)
    }
}

function Test-DeviceOpen {
    param(
        [string[]]$DevicePaths,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastAttempts = @()
    $genericReadWrite = [uint32]3221225472 # 0xC0000000 (GENERIC_READ | GENERIC_WRITE)
    $metadataAccess = [uint32]0

    do {
        $lastAttempts = @()
        foreach ($devicePath in $DevicePaths) {
            $rwAttempt = Try-OpenDevicePath -DevicePath $devicePath -DesiredAccess $genericReadWrite -AccessLabel "rw"
            $lastAttempts += $rwAttempt
            if ($rwAttempt.Success) {
                return [pscustomobject]@{
                    Path = $rwAttempt.Path
                    Attempts = $lastAttempts
                }
            }

            # Fallback probe: validate object existence even if rw access is denied.
            $metadataAttempt = Try-OpenDevicePath -DevicePath $devicePath -DesiredAccess $metadataAccess -AccessLabel "metadata"
            $lastAttempts += $metadataAttempt
            if ($metadataAttempt.Success) {
                return [pscustomobject]@{
                    Path = $metadataAttempt.Path
                    Attempts = $lastAttempts
                }
            }
        }

        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    return [pscustomobject]@{
        Path = $null
        Attempts = $lastAttempts
    }
}

Assert-AdminContext

$resolvedDriverPath = Resolve-DriverPath -PreferredPath $DriverPath
if (-not $resolvedDriverPath) {
    Write-Host "Driver not found at expected locations."
    Write-Host "Run .\scripts\build_driver.ps1 first, then re-run install."
    exit 1
}

if ($TestSigning) {
    Write-Host "Enabling test signing (requires reboot)..."
    & bcdedit /set testsigning on | Out-Null
    Write-Host "Reboot, then run this script again without -TestSigning."
    exit 0
}

$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$serviceExists = $null -ne $existingService
if ($serviceExists) {
    Write-Host "Service '$ServiceName' already exists; attempting in-place update."
    & sc.exe stop $ServiceName *> $null
    Start-Sleep -Milliseconds 800
}

$targetDir = "C:\ProgramData\Quoodle"
$targetPath = Join-Path $targetDir ("quoodle_kmdf_{0}.sys" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
try {
    Copy-Item -Force $resolvedDriverPath $targetPath
} catch {
    $versionedPath = Join-Path $targetDir ("quoodle_kmdf_{0}_retry.sys" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    Copy-Item -Force $resolvedDriverPath $versionedPath
    $targetPath = $versionedPath
    Write-Warning "Primary driver path was locked. Using versioned install path: $targetPath"
}

$sig = Get-AuthenticodeSignature -FilePath $targetPath
if ($sig.Status -eq "NotSigned") {
    throw "Driver binary is unsigned ($targetPath). Rebuild with test-sign enabled: .\scripts\build_driver.ps1 -Configuration Release -Platform x64 -DisableTestSign:`$false"
}
if ($sig.Status -eq "UnknownError" -and $sig.StatusMessage -match "not trusted") {
    $thumbprint = if ($sig.SignerCertificate) { $sig.SignerCertificate.Thumbprint } else { "<unknown>" }
    throw "Driver signature is present but not trusted on this machine (thumbprint: $thumbprint). Import signer cert to LocalMachine\\Root and LocalMachine\\TrustedPublisher, then retry."
}

if ($serviceExists) {
    Write-Host "Updating service '$ServiceName' binary path..."
    $configOutput = & sc.exe config $ServiceName type= kernel start= demand binPath= $targetPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = ($configOutput | Out-String).Trim()
        throw "Failed to update service '$ServiceName'. sc.exe exit=$LASTEXITCODE. $details"
    }
} else {
    Write-Host "Creating service '$ServiceName'..."
    $createOutput = & sc.exe create $ServiceName type= kernel start= demand binPath= $targetPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = ($createOutput | Out-String).Trim()
        throw "Failed to create service '$ServiceName'. sc.exe exit=$LASTEXITCODE. $details"
    }
}

$serviceCheck = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $serviceCheck) {
    throw "Service '$ServiceName' was not created."
}

$paramsPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName\Parameters"
New-Item -Path $paramsPath -Force | Out-Null
if ([string]::IsNullOrWhiteSpace($HmacKey)) {
    Write-Warning "No HMAC key provided. Strict transport validation will reject signed IOCTL flow until key is set."
} else {
    New-ItemProperty -Path $paramsPath -Name "HmacKey" -Value $HmacKey -PropertyType String -Force | Out-Null
    $stored = (Get-ItemProperty -Path $paramsPath -Name "HmacKey" -ErrorAction Stop).HmacKey
    if ($stored -ne $HmacKey) {
        throw "HMAC registry write/readback mismatch under '$paramsPath'."
    }
}

Write-Host "Service config:"
& sc.exe qc $ServiceName

if ($NoStart) {
    Write-Warning "NoStart was specified; driver service was installed but not started."
    Write-Host "Installed path: $targetPath"
    Write-Host "Service name:   $ServiceName"
    exit 0
}

$startOutput = & sc.exe start $ServiceName 2>&1
$startDetails = ($startOutput | Out-String).Trim()
$queryOutput = & sc.exe query $ServiceName 2>&1
$queryDetails = ($queryOutput | Out-String).Trim()

$stateCode = 0
$win32ExitCode = 0
if ($queryDetails -match "STATE\s+:\s+(\d+)") {
    $stateCode = [int]$matches[1]
}
if ($queryDetails -match "WIN32_EXIT_CODE\s+:\s+(\d+)") {
    $win32ExitCode = [int]$matches[1]
}

# `sc.exe` can return 0 even when service start failed, so rely on query state + Win32 exit code.
if ($stateCode -ne 4) {
    $hint = ""
    if ($win32ExitCode -eq 577) {
        $hint = " Driver signature enforcement blocked the load (577). For local dev builds: run install script with -TestSigning, reboot, and ensure Windows test mode is enabled. If still blocked, disable Core Isolation > Memory Integrity for dev testing."
    }
    throw "Failed to start service '$ServiceName'. Start output: $startDetails`nQuery output: $queryDetails$hint"
}

if (-not (Wait-ServiceRunning -Name $ServiceName -TimeoutSeconds 20)) {
    & sc.exe query $ServiceName
    throw "Service '$ServiceName' did not reach Running state."
}

$deviceCandidates = @(
    "\\.\QuoodleKernel",
    "\\.\Global\QuoodleKernel",
    "\\.\GLOBALROOT\Device\QuoodleKernel",
    "\\?\GLOBALROOT\Device\QuoodleKernel"
)

$probe = Test-DeviceOpen -DevicePaths $deviceCandidates -TimeoutSeconds 20
if (-not $probe.Path) {
    $diagnostics = $probe.Attempts | ForEach-Object {
        "{0} [{1}] => {2} ({3})" -f $_.Path, $_.Access, $_.ErrorCode, $_.ErrorMessage
    }
    throw "Service is running, but no device path is reachable after 20s. Tried: $($deviceCandidates -join ', '). Diagnostics: $($diagnostics -join '; ')"
}

Write-Host "Driver installed and verified."
Write-Host "Source driver:  $resolvedDriverPath"
Write-Host "Installed path: $targetPath"
Write-Host "Service state:  Running ($ServiceName)"
Write-Host "Device path:    $($probe.Path)"
