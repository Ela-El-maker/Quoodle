# ===== App Lock: WhatsApp (exact script) =====
$ErrorActionPreference = "Stop"

if (-not $jwt) { throw "Set `$jwt first." }

$baseUrl = "http://localhost:8088"
$headers = @{
  Authorization = "Bearer $jwt"
  "Content-Type" = "application/json"
}

# 0) Point to latest agent log (prevents $log null)
$log = (Get-ChildItem "C:\Users\felix\Work-Force\Quoodle\logs\agent_e2e_*.out.log" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1).FullName
if (-not $log) { throw "No agent log found in C:\Users\felix\Work-Force\Quoodle\logs" }
"`nUsing log: $log`n"

# 1) Clear old app-lock policy
$existing = Invoke-RestMethod -Uri "$baseUrl/api/policy/app-lock" -Method Get -Headers @{ Authorization = "Bearer $jwt" }
$existingPolicy = $existing.app_lock
$existingRules = @()
if ($null -ne $existingPolicy -and $null -ne $existingPolicy.rules) {
  foreach ($r in $existingPolicy.rules) {
    $value = ($r.value -as [string]).ToLowerInvariant()
    if (($r.match_type -as [string]) -eq "basename" -and ($value -eq "whatsapp.root.exe" -or $value -eq "whatsapp.exe")) {
      continue
    }
    $existingRules += $r
  }
}

# 2) Push new block policy
$body = @{
  enabled = $true
  mode = if ($existingPolicy -and $existingPolicy.mode) { $existingPolicy.mode } else { "blocklist" }
  fail_mode = if ($existingPolicy -and $existingPolicy.fail_mode) { $existingPolicy.fail_mode } else { "open" }
  event_dedupe_sec = if ($existingPolicy -and $existingPolicy.event_dedupe_sec) { [int]$existingPolicy.event_dedupe_sec } else { 30 }
  rules = @($existingRules + @(
    @{
      rule_id = "block-whatsapp-root-basename"
      match_type = "basename"
      value = "whatsapp.root.exe"
      action = "block"
      priority = 10
      expires_at = $null
    },
    @{
      rule_id = "block-whatsapp-exe-basename"
      match_type = "basename"
      value = "whatsapp.exe"
      action = "block"
      priority = 20
      expires_at = $null
    }
  ))
} | ConvertTo-Json -Depth 8

Invoke-RestMethod -Uri "$baseUrl/api/policy/app-lock" -Method Put -Headers $headers -Body $body | Format-List

Start-Sleep -Seconds 2

# 3) Verify kernel actually armed callback
$statusLines = Get-Content $log -Tail 300 |
  Select-String "app_lock kernel status after apply|callback_registered|apply failed|policy updated" -CaseSensitive:$false

"`nRecent app-lock status lines:`n"
$statusLines | ForEach-Object { $_.Line }

$latestStatusLine = ($statusLines | Where-Object { $_.Line -match "app_lock kernel status after apply" } | Select-Object -Last 1).Line
if ($latestStatusLine -and $latestStatusLine -match 'callback_registered":(true|false)') {
  $callbackState = $matches[1]
  "`ncallback_registered=$callbackState`n"
}

"`nIf you see callback_registered:true and rule_count>=1, enforcement is active.`n"

# 4) Kill already running WhatsApp (policy blocks new launches, not existing one)
Get-Process -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like "WhatsApp*" } |
  Stop-Process -Force -ErrorAction SilentlyContinue

# 5) Check if it re-launched
Start-Sleep -Seconds 2
Get-CimInstance Win32_Process |
  Where-Object { $_.Name -like "*WhatsApp*" } |
  Select-Object Name, ExecutablePath
