param(
    [Parameter(Mandatory = $true)]
    [string]$Basename,
    [string]$Jwt,
    [string]$BaseUrl = "http://localhost:8088",
    [int]$Priority = 10,
    [int]$EventDedupeSec = 30,
    [switch]$ReplacePolicy,
    [switch]$KillRunning
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Jwt)) {
    if (-not [string]::IsNullOrWhiteSpace($script:jwt)) {
        $Jwt = $script:jwt
    } elseif (-not [string]::IsNullOrWhiteSpace($global:jwt)) {
        $Jwt = $global:jwt
    }
}

if ([string]::IsNullOrWhiteSpace($Jwt)) {
    throw "JWT missing. Pass -Jwt or set `$jwt first."
}

$normalizedBasename = $Basename.Trim().ToLowerInvariant()
if (-not $normalizedBasename.EndsWith(".exe")) {
    throw "Basename must be an executable name ending in .exe (example: whatsapp.root.exe)."
}

$headers = @{
    Authorization = "Bearer $Jwt"
    "Content-Type" = "application/json"
}

$ruleIdSafe = ($normalizedBasename -replace "[^a-z0-9\.-]", "-")
$ruleId = "block-$ruleIdSafe-basename"

$existingRules = @()
$existingPolicy = $null
if (-not $ReplacePolicy) {
    $existing = Invoke-RestMethod -Uri "$BaseUrl/api/policy/app-lock" -Method Get -Headers @{ Authorization = "Bearer $Jwt" }
    if ($null -ne $existing -and $null -ne $existing.app_lock) {
        $existingPolicy = $existing.app_lock
    }
    if ($null -ne $existingPolicy -and $null -ne $existingPolicy.rules) {
        foreach ($r in $existingPolicy.rules) {
            if ($r.match_type -eq "basename" -and ($r.value -as [string]).ToLowerInvariant() -eq $normalizedBasename) {
                continue
            }
            $existingRules += $r
        }
    }
}

$newRule = @{
    rule_id = $ruleId
    match_type = "basename"
    value = $normalizedBasename
    action = "block"
    priority = $Priority
    expires_at = $null
}

$rules = @($newRule)
if ($existingRules.Count -gt 0) {
    $rules = @($existingRules + $newRule)
}

$body = @{
    enabled = $true
    mode = if ($existingPolicy -and $existingPolicy.mode) { $existingPolicy.mode } else { "blocklist" }
    fail_mode = if ($existingPolicy -and $existingPolicy.fail_mode) { $existingPolicy.fail_mode } else { "open" }
    event_dedupe_sec = if ($EventDedupeSec -gt 0) { $EventDedupeSec } elseif ($existingPolicy -and $existingPolicy.event_dedupe_sec) { [int]$existingPolicy.event_dedupe_sec } else { 30 }
    rules = $rules
} | ConvertTo-Json -Depth 10

$resp = Invoke-RestMethod -Uri "$BaseUrl/api/policy/app-lock" -Method Put -Headers $headers -Body $body
$resp | Format-List

if ($KillRunning) {
    $processPrefix = [System.IO.Path]::GetFileNameWithoutExtension($normalizedBasename)
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.ToLowerInvariant() -eq $processPrefix } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Policy applied for basename: $normalizedBasename"
Write-Host "Rule ID: $ruleId"
Write-Host "Rule count (pushed): $($rules.Count)"
