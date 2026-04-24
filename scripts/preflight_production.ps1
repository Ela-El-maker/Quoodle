param(
    [string]$EnvFile = ".env.production",
    [string]$ComposeFile = "docker-compose.prod.yml"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Ok($msg) { Write-Host "[OK]  $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red }

if (-not (Test-Path -LiteralPath $EnvFile)) {
    Write-Fail "Missing env file: $EnvFile"
    exit 1
}

if (-not (Test-Path -LiteralPath $ComposeFile)) {
    Write-Fail "Missing compose file: $ComposeFile"
    exit 1
}

$envMap = @{}
Get-Content -LiteralPath $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $idx = $line.IndexOf("=")
    if ($idx -lt 1) { return }
    $k = $line.Substring(0, $idx).Trim()
    $v = $line.Substring($idx + 1).Trim()
    $envMap[$k] = $v
}

$requiredKeys = @(
    "APP_ENV", "APP_DEBUG", "APP_KEY",
    "CONTROL_PLANE_IMAGE", "CONTROL_PLANE_UI_IMAGE", "GATEWAY_IMAGE",
    "DB_HOST", "DB_DATABASE", "DB_USERNAME", "DB_PASSWORD",
    "REDIS_HOST", "REDIS_URL",
    "POLICY_HASH", "POLICY_VERSION", "CONTROLLER_ID",
    "LARAVEL_SERVICE_PRIVATE_KEY_B64", "LARAVEL_SERVICE_PUBKEY_B64",
    "FASTAPI_SERVICE_PRIVATE_KEY_B64", "FASTAPI_SERVICE_PUBLIC_KEY_B64",
    "ED25519_PRIVATE_KEY_B64",
    "MAIL_HOST", "MAIL_USERNAME", "MAIL_PASSWORD", "MAIL_FROM_ADDRESS"
)

$placeholderPatterns = @(
    "<.+>",
    "^replace_me$",
    "^change_me$"
)

$missing = New-Object System.Collections.Generic.List[string]
$placeholderHits = New-Object System.Collections.Generic.List[string]

foreach ($key in $requiredKeys) {
    if (-not $envMap.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($envMap[$key])) {
        $missing.Add($key)
        continue
    }
    foreach ($pattern in $placeholderPatterns) {
        if ($envMap[$key] -match $pattern) {
            $placeholderHits.Add($key)
            break
        }
    }
}

if ($missing.Count -gt 0) {
    Write-Fail "Missing required keys: $($missing -join ', ')"
}

if ($placeholderHits.Count -gt 0) {
    Write-Fail "Placeholder values detected: $($placeholderHits -join ', ')"
}

if ($missing.Count -gt 0 -or $placeholderHits.Count -gt 0) {
    exit 1
}

Write-Ok "Required keys are present."

$appEnv = $envMap["APP_ENV"]
$appDebug = $envMap["APP_DEBUG"]
$allowDevFallback = $envMap["ALLOW_DEV_SIG_FALLBACK"]
$enableTests = $envMap["ENABLE_TEST_ENDPOINTS"]
$runMigrations = $envMap["RUN_MIGRATIONS_ON_BOOT"]
$runEmbeddedWorker = $envMap["RUN_QUEUE_WORKER_IN_WEB"]

if ($appEnv -ne "production") {
    Write-Warn "APP_ENV is '$appEnv' (recommended: production)"
}
if ($appDebug -ne "false") {
    Write-Warn "APP_DEBUG is '$appDebug' (recommended: false)"
}
if ($allowDevFallback -eq "true") {
    Write-Fail "ALLOW_DEV_SIG_FALLBACK must be false in production"
    exit 1
}
if ($enableTests -eq "true") {
    Write-Fail "ENABLE_TEST_ENDPOINTS must be false in production"
    exit 1
}
if ($runMigrations -eq "true") {
    Write-Warn "RUN_MIGRATIONS_ON_BOOT=true. Prefer running migrations as a controlled rollout step."
}
if ($runEmbeddedWorker -eq "true") {
    Write-Warn "RUN_QUEUE_WORKER_IN_WEB=true. Prefer dedicated worker container in production."
}

Write-Host "Validating compose rendering..." -ForegroundColor Cyan
docker compose --env-file $EnvFile -f $ComposeFile config > $null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "docker compose config validation failed"
    exit 1
}
Write-Ok "docker compose config validation passed."

Write-Host ""
Write-Ok "Production preflight passed for $EnvFile using $ComposeFile."
