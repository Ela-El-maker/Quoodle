param(
    [Parameter(Mandatory = $true)]
    [string]$Basename,
    [string]$Jwt,
    [string]$BaseUrl = "http://localhost:8088"
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
    throw "Basename must end in .exe (example: whatsapp.root.exe)."
}

$headers = @{
    Authorization = "Bearer $Jwt"
    "Content-Type" = "application/json"
}

$current = Invoke-RestMethod -Uri "$BaseUrl/api/policy/app-lock" -Method Get -Headers @{ Authorization = "Bearer $Jwt" }
$currentPolicy = $current.app_lock

if ($null -eq $currentPolicy -or $null -eq $currentPolicy.rules) {
    Write-Host "No app-lock policy/rules found. Nothing to unblock."
    exit 0
}

$rules = @()
$removed = 0
foreach ($r in $currentPolicy.rules) {
    $isMatch = $false
    if (($r.match_type -as [string]) -eq "basename") {
        $value = ($r.value -as [string]).ToLowerInvariant()
        if ($value -eq $normalizedBasename) {
            $isMatch = $true
        }
    }
    if ($isMatch) {
        $removed++
        continue
    }
    $rules += $r
}

if ($removed -eq 0) {
    Write-Host "App was not blocked by basename rule: $normalizedBasename"
    exit 0
}

if ($rules.Count -eq 0) {
    $resp = Invoke-RestMethod -Uri "$BaseUrl/api/policy/app-lock" -Method Delete -Headers @{ Authorization = "Bearer $Jwt" }
    $resp | Format-List
    Write-Host ""
    Write-Host "Removed $removed rule(s). Policy is now cleared."
    exit 0
}

$body = @{
    enabled = $true
    mode = if ($currentPolicy.mode) { $currentPolicy.mode } else { "blocklist" }
    fail_mode = if ($currentPolicy.fail_mode) { $currentPolicy.fail_mode } else { "open" }
    event_dedupe_sec = if ($currentPolicy.event_dedupe_sec) { [int]$currentPolicy.event_dedupe_sec } else { 30 }
    rules = $rules
} | ConvertTo-Json -Depth 10

$resp = Invoke-RestMethod -Uri "$BaseUrl/api/policy/app-lock" -Method Put -Headers $headers -Body $body
$resp | Format-List

Write-Host ""
Write-Host "Removed $removed rule(s) for $normalizedBasename. Remaining rules: $($rules.Count)"
