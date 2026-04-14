param(
    [Parameter(Mandatory = $true)]
    [string]$Basename,
    [string]$Jwt,
    [string]$BaseUrl = "http://localhost:8088",
    [switch]$ShowMatches
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

$current = Invoke-RestMethod -Uri "$BaseUrl/api/policy/app-lock" -Method Get -Headers @{ Authorization = "Bearer $Jwt" }
$policy = $current.app_lock

$matches = @()
if ($null -ne $policy -and $null -ne $policy.rules) {
    foreach ($r in $policy.rules) {
        if (($r.match_type -as [string]) -ne "basename") {
            continue
        }
        $value = ($r.value -as [string]).ToLowerInvariant()
        if ($value -eq $normalizedBasename) {
            $matches += $r
        }
    }
}

$isBlocked = $false
if ($null -ne $policy) {
    $isBlocked = [bool]$policy.enabled -and ($matches.Count -gt 0)
}

$result = [pscustomobject]@{
    basename = $normalizedBasename
    blocked = $isBlocked
    policy_enabled = if ($null -ne $policy) { [bool]$policy.enabled } else { $false }
    total_rules = if ($null -ne $policy -and $null -ne $policy.rules) { @($policy.rules).Count } else { 0 }
    matching_rules = $matches.Count
    policy_version = if ($null -ne $policy) { $policy.policy_version } else { $null }
    policy_hash = if ($null -ne $policy) { $policy.policy_hash } else { $null }
}

$result | Format-List

if ($ShowMatches -and $matches.Count -gt 0) {
    Write-Host ""
    Write-Host "Matching rules:"
    $matches | ConvertTo-Json -Depth 10
}
