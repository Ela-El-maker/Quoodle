param(
    [string]$ExePath = "$PSScriptRoot\\..\\build\\Release\\agent.exe",
    [string]$ServiceName = "QuoodleAgent",
    [string]$DisplayName = "Quoodle Agent",
    [string]$Description = "Quoodle endpoint agent service",
    [string]$StartType = "auto",
    [switch]$DelayedAutoStart,
    [int]$RestartDelayMs = 5000,
    [string]$ControllerPubKeyPath = "C:\ProgramData\Quoodle\controller_pubkey.b64"
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
        IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "Administrator privileges are required to install Windows services. Re-run this script in an elevated PowerShell."
    }
}

function Invoke-Sc {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [int[]]$IgnoreExitCodes = @()
    )

    $output = & sc.exe @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0 -and $IgnoreExitCodes -notcontains $code) {
        $joined = ($output | Out-String).Trim()
        throw "sc.exe $($Arguments -join ' ') failed (exit $code): $joined"
    }

    return $output
}

function Convert-ToServiceStartupType {
    param([string]$Value)

    $normalized = ""
    if ($null -ne $Value) {
        $normalized = $Value.Trim().ToLowerInvariant()
    }

    switch ($normalized) {
        "auto" { return "Automatic" }
        "delayed-auto" { return "Automatic" }
        "demand" { return "Manual" }
        "disabled" { return "Disabled" }
        default { return "Automatic" }
    }
}

function Set-ServiceEnvironmentDefaults {
    param(
        [Parameter(Mandatory = $true)][string]$ServiceName,
        [Parameter(Mandatory = $true)][string]$ControllerPubKeyPath
    )

    $serviceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    $desiredVars = @(
        "QUOODLE_USE_KERNEL_DRIVER=1",
        "QUOODLE_ALLOW_PIPE_FALLBACK=0",
        "CONTROLLER_PUBKEY_PATH=$ControllerPubKeyPath"
    )

    $existingVars = @()
    try {
        $current = (Get-ItemProperty -Path $serviceRegPath -Name Environment -ErrorAction SilentlyContinue).Environment
        if ($current) {
            if ($current -is [System.Array]) {
                $existingVars = @($current)
            } else {
                $existingVars = @([string]$current)
            }
        }
    } catch {
        $existingVars = @()
    }

    $filteredExisting = @()
    foreach ($entry in $existingVars) {
        if (-not $entry) { continue }
        if ($entry -like "QUOODLE_USE_KERNEL_DRIVER=*") { continue }
        if ($entry -like "QUOODLE_ALLOW_PIPE_FALLBACK=*") { continue }
        if ($entry -like "CONTROLLER_PUBKEY_PATH=*") { continue }
        $filteredExisting += [string]$entry
    }

    $newVars = @($filteredExisting + $desiredVars)
    Set-ItemProperty -Path $serviceRegPath -Name Environment -Value $newVars -Type MultiString
}

function Ensure-ControllerPubKeyFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (Test-Path $Path) {
        $existing = (Get-Content -Path $Path -ErrorAction SilentlyContinue | Out-String).Trim()
        if ($existing) {
            return
        }
    }

    $pubKey = $null
    if ($env:CONTROLLER_PUBKEY_B64) {
        $pubKey = $env:CONTROLLER_PUBKEY_B64.Trim()
    }

    if (-not $pubKey) {
        $docker = Get-Command docker -ErrorAction SilentlyContinue
        if ($docker) {
            try {
                $py = @'
import os
import base64
import sys

sk_b64 = os.getenv("ED25519_PRIVATE_KEY_B64")
if not sk_b64:
    sk_path = os.getenv("ED25519_PRIVATE_KEY_PATH")
    if sk_path and os.path.exists(sk_path):
        try:
            with open(sk_path, "r", encoding="utf-8") as f:
                sk_b64 = f.read().strip()
        except Exception:
            sk_b64 = None

if not sk_b64:
    print("")
    sys.exit(0)

try:
    raw = base64.b64decode(sk_b64)
except Exception:
    print("")
    sys.exit(0)

pub = b""
if len(raw) == 64:
    pub = raw[32:64]
elif len(raw) == 32:
    try:
        from nacl.signing import SigningKey
        pub = SigningKey(raw).verify_key.encode()
    except Exception:
        pub = b""

if not pub:
    print("")
    sys.exit(0)

print(base64.b64encode(pub).decode())
'@
                $pubKey = ($py | docker exec -i quoodle-gateway python - 2>$null | Out-String).Trim()
            } catch {
                # Best effort only.
            }
        }
    }

    if ($pubKey) {
        Set-Content -Path $Path -Value $pubKey -NoNewline
        Write-Host "Wrote controller public key to: $Path"
    } else {
        Write-Warning "CONTROLLER_PUBKEY_B64 was not available and $Path is empty. Populate it manually so signed commands can be verified."
    }
}

function Wait-ForServiceDeletion {
    param(
        [Parameter(Mandatory = $true)][string]$ServiceName,
        [int]$TimeoutSeconds = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $exists = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $exists) {
            return $true
        }
        Start-Sleep -Milliseconds 750
    }

    return $false
}

function New-ServiceWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$BinaryPathName,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][string]$StartupType,
        [int]$MaxAttempts = 20,
        [int]$DelaySeconds = 2
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            New-Service `
                -Name $Name `
                -BinaryPathName $BinaryPathName `
                -DisplayName $DisplayName `
                -Description $Description `
                -StartupType $StartupType `
                -ErrorAction Stop | Out-Null
            return
        } catch {
            $message = $_.Exception.Message
            $isMarkedForDeletion = $message -match 'marked for deletion'
            if (-not $isMarkedForDeletion -or $attempt -eq $MaxAttempts) {
                throw
            }
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

if (!(Test-Path $ExePath)) {
    Write-Host "Agent executable not found: $ExePath"
    exit 1
}

Assert-Admin

Invoke-Sc -Arguments @("stop", $ServiceName) -IgnoreExitCodes @(1060, 1062) | Out-Null
Invoke-Sc -Arguments @("delete", $ServiceName) -IgnoreExitCodes @(1060, 1072) | Out-Null

if (-not (Wait-ForServiceDeletion -ServiceName $ServiceName -TimeoutSeconds 60)) {
    throw "Service '$ServiceName' is still marked for deletion after waiting. Close Services.msc/Task Manager service views, then rerun the script."
}

$quotedBin = '"' + $ExePath + '" --service'
$startupType = Convert-ToServiceStartupType -Value $StartType
New-ServiceWithRetry `
    -Name $ServiceName `
    -BinaryPathName $quotedBin `
    -DisplayName $DisplayName `
    -Description $Description `
    -StartupType $startupType

Set-ServiceEnvironmentDefaults -ServiceName $ServiceName -ControllerPubKeyPath $ControllerPubKeyPath
Ensure-ControllerPubKeyFile -Path $ControllerPubKeyPath

if ($DelayedAutoStart) {
    Invoke-Sc -Arguments @("config", $ServiceName, "start=", "delayed-auto") | Out-Null
}

# Service recovery: always restart on crash/abnormal stop.
$restartActions = "restart/$RestartDelayMs/restart/$RestartDelayMs/restart/$RestartDelayMs"
Invoke-Sc -Arguments @("failure", $ServiceName, "reset=", "86400", "actions=", $restartActions) | Out-Null
Invoke-Sc -Arguments @("failureflag", $ServiceName, "1") | Out-Null

Invoke-Sc -Arguments @("start", $ServiceName) | Out-Null

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Error "Service install failed: $ServiceName not found"
    exit 1
}
if ($service.Status -ne 'Running') {
    Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $service.Refresh()
}

if ($service.Status -ne 'Running') {
    Write-Error "Service is not running: $ServiceName"
    exit 1
}

Write-Host "Installed and running service: $ServiceName"
