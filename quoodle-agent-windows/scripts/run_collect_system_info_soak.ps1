param(
    [int]$DurationSeconds = 200,
    [int]$IntervalMs = 1000,
    [int]$LatencySlaMs = 2000,
    [string]$OutputPath = "",
    [switch]$AllowPipeFallback,
    [switch]$SkipPreflight
)

$ErrorActionPreference = "Stop"

function Resolve-SoakBinaryPath {
    param([string]$RepoRoot)

    $candidates = @(
        (Join-Path $RepoRoot "build_collectinfo\Release\collect_system_info_soak.exe"),
        (Join-Path $RepoRoot "build\Release\collect_system_info_soak.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "collect_system_info_soak.exe not found. Build it first (target: collect_system_info_soak)."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$binaryPath = Resolve-SoakBinaryPath -RepoRoot $repoRoot

try {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Warning "Not running as Administrator. Driver IOCTL open may fail in strict KMDF mode."
    }
} catch {
    Write-Warning "Unable to determine Administrator status: $($_.Exception.Message)"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputPath = Join-Path $repoRoot "logs\collect_system_info_soak_$timestamp.json"
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$env:QUOODLE_USE_KERNEL_DRIVER = "1"
$env:QUOODLE_ALLOW_PIPE_FALLBACK = $(if ($AllowPipeFallback) { "1" } else { "0" })

if ([string]::IsNullOrWhiteSpace($env:QUOODLE_DRIVER_HMAC_KEY)) {
    throw "QUOODLE_DRIVER_HMAC_KEY is missing in this shell. Set it before running soak."
}

$driverService = Get-Service -Name "QuoodleKernel" -ErrorAction SilentlyContinue
if (-not $driverService) {
    throw "QuoodleKernel service is not installed. Install/start the KMDF driver first."
}
if ($driverService.Status -ne "Running") {
    throw "QuoodleKernel service is not running (status=$($driverService.Status)). Start it before soak."
}

Write-Host "Running collect_system_info soak harness..." -ForegroundColor Cyan
Write-Host "Binary: $binaryPath"
Write-Host "DurationSeconds=$DurationSeconds IntervalMs=$IntervalMs LatencySlaMs=$LatencySlaMs"
Write-Host "QUOODLE_USE_KERNEL_DRIVER=$($env:QUOODLE_USE_KERNEL_DRIVER) QUOODLE_ALLOW_PIPE_FALLBACK=$($env:QUOODLE_ALLOW_PIPE_FALLBACK)"
Write-Host "Summary output: $OutputPath"

if (-not $SkipPreflight) {
    $preflightOutput = Join-Path $outputDir ("collect_system_info_soak_preflight_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    Write-Host ""
    Write-Host "Running preflight soak (5s)..." -ForegroundColor Yellow
    & $binaryPath `
        --duration-seconds 5 `
        --interval-ms 500 `
        --latency-sla-ms $LatencySlaMs `
        --output $preflightOutput
    if ($LASTEXITCODE -ne 0) {
        $preflight = Get-Content -Raw $preflightOutput | ConvertFrom-Json
        $errorCodes = if ($preflight.error_code_counts) { ($preflight.error_code_counts | ConvertTo-Json -Compress) } else { "{}" }
        $win32ErrorCodes = if ($preflight.win32_error_counts) { ($preflight.win32_error_counts | ConvertTo-Json -Compress) } else { "{}" }
        $errorMessages = if ($preflight.error_message_counts) { ($preflight.error_message_counts | ConvertTo-Json -Compress) } else { "{}" }
        throw "Preflight failed. error_code_counts=$errorCodes win32_error_counts=$win32ErrorCodes error_message_counts=$errorMessages"
    }
}

& $binaryPath `
    --duration-seconds $DurationSeconds `
    --interval-ms $IntervalMs `
    --latency-sla-ms $LatencySlaMs `
    --output $OutputPath

$exitCode = $LASTEXITCODE

if (-not (Test-Path $OutputPath)) {
    throw "Soak summary output file not produced: $OutputPath"
}

$summary = Get-Content -Raw $OutputPath | ConvertFrom-Json
$status = if ($summary.pass) { "PASS" } else { "FAIL" }
$color = if ($summary.pass) { "Green" } else { "Red" }

Write-Host ""
Write-Host "collect_system_info soak result: $status" -ForegroundColor $color
Write-Host "iterations=$($summary.iterations) success=$($summary.success) failed=$($summary.failed) success_rate_pct=$([math]::Round([double]$summary.success_rate_pct, 2))"
Write-Host "latency_p95_ms=$($summary.latency_p95_ms) fail_open_fallback_events=$($summary.fail_open_fallback_events) signature_errors=$($summary.signature_errors) version_errors=$($summary.version_errors)"

exit $exitCode
