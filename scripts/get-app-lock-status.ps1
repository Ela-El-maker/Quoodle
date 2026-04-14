param(
    [string]$Jwt,
    [string]$BaseUrl = "http://localhost:8088",
    [switch]$ShowAgentLog
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

$status = Invoke-RestMethod -Uri "$BaseUrl/api/policy/app-lock" -Method Get -Headers @{ Authorization = "Bearer $Jwt" }
$status | ConvertTo-Json -Depth 10

if ($ShowAgentLog) {
    $log = (Get-ChildItem "C:\Users\felix\Work-Force\Quoodle\logs\agent_e2e_*.out.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1).FullName

    if ([string]::IsNullOrWhiteSpace($log)) {
        Write-Warning "No agent log found."
        exit 0
    }

    Write-Host ""
    Write-Host "Latest agent log: $log"
    Get-Content $log -Tail 300 |
        Select-String "app_lock kernel status after apply|app_lock kernel status after clear|callback_registered|callback_register_status_hex|app_lock apply failed|policy updated" -CaseSensitive:$false
}
