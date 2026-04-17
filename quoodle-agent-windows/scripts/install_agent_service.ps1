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
        "CONTROLLER_PUBKEY_PATH=$ControllerPubKeyPath",
        # Explicitly clear any stale machine-level guard so service auth is not
        # blocked by old AGENT_EXPECTED_PUBKEY_B64 values after re-pairing.
        "AGENT_EXPECTED_PUBKEY_B64="
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
        if ($entry -like "AGENT_EXPECTED_PUBKEY_B64=*") { continue }
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

    $existing = ""
    if (Test-Path $Path) {
        $existing = (Get-Content -Path $Path -ErrorAction SilentlyContinue | Out-String).Trim()
    }

    $pubKey = $null
    $pubKeySource = ""

    # Prefer the currently running gateway signing key endpoint so the agent verifier
    # always matches the live signer used for COMMAND_DELIVERY envelopes.
    $agentEndpoint = $null
    if ($env:AGENT_ENDPOINT) {
        $agentEndpoint = $env:AGENT_ENDPOINT.Trim()
    }
    if (-not $agentEndpoint -and (Test-Path "C:\ProgramData\Quoodle\agent_endpoint")) {
        $agentEndpoint = (Get-Content "C:\ProgramData\Quoodle\agent_endpoint" -ErrorAction SilentlyContinue | Out-String).Trim()
    }
    if (-not $agentEndpoint) {
        $agentEndpoint = "ws://localhost:8000/agent"
    }

    try {
        $base = $agentEndpoint.Trim()
        $base = $base -replace '^wss://', 'https://'
        $base = $base -replace '^ws://', 'http://'
        $uri = [System.Uri]$base
        $signingKeyUrl = "$($uri.Scheme)://$($uri.Authority)/api/v1/controller/signing-key"
        $resp = Invoke-RestMethod -Method Get -Uri $signingKeyUrl -TimeoutSec 3 -ErrorAction Stop
        if ($resp -and $resp.controller_pubkey_b64) {
            $pubKey = [string]$resp.controller_pubkey_b64
            $pubKeySource = "gateway-signing-key-endpoint"
        }
    } catch {
        # Best effort only; fall back to static/env/docker sources below.
    }

    if (-not $pubKey -and $env:CONTROLLER_PUBKEY_B64) {
        $pubKey = $env:CONTROLLER_PUBKEY_B64.Trim()
        $pubKeySource = "CONTROLLER_PUBKEY_B64"
    }

    if (-not $pubKey) {
        $docker = Get-Command docker -ErrorAction SilentlyContinue
        if ($docker) {
            try {
                $gatewayPubEnv = (& docker exec quoodle-gateway /bin/sh -lc "printenv ED25519_PUBLIC_KEY_B64" 2>$null | Out-String).Trim()
                if ($gatewayPubEnv) {
                    $pubKey = $gatewayPubEnv
                    $pubKeySource = "quoodle-gateway:ED25519_PUBLIC_KEY_B64"
                }
            } catch {
                # Best effort only.
            }
        }
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
                if ($pubKey) {
                    $pubKeySource = "quoodle-gateway:ED25519_PRIVATE_KEY_B64/ED25519_PRIVATE_KEY_PATH"
                }
            } catch {
                # Best effort only.
            }
        }
    }

    if ($pubKey) {
        if ($existing -eq $pubKey) {
            Write-Host "Controller public key already up to date at: $Path"
            return
        }

        Set-Content -Path $Path -Value $pubKey -NoNewline
        if ($existing) {
            Write-Host "Updated controller public key at: $Path (source: $pubKeySource)"
        } else {
            Write-Host "Wrote controller public key to: $Path (source: $pubKeySource)"
        }
    } else {
        if ($existing) {
            Write-Warning "Could not resolve current controller public key from env/docker; keeping existing value in $Path."
        } else {
            Write-Warning "CONTROLLER_PUBKEY_B64 was not available and $Path is empty. Populate it manually so signed commands can be verified."
        }
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
