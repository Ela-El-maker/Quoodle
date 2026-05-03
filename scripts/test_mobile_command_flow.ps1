param(
    [Parameter(Mandatory = $true)]
    [string]$Jwt,

    [Parameter(Mandatory = $true)]
    [string]$DeviceId,

    [string]$BaseUrl = "http://161.35.62.116:8088",
    [string]$Method = "list_processes",
    [string]$ParamsJson = '{"limit":25}',
    [switch]$Sensitive,
    [string]$TwoFactorCode = "",
    [int]$TimeoutSeconds = 90,
    [int]$PollSeconds = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Stage {
    param([string]$Message)
    Write-Host "[mobile-flow] $Message"
}

function Invoke-ApiJson {
    param(
        [ValidateSet("GET", "POST")]
        [string]$MethodName,
        [string]$Url,
        [hashtable]$Headers,
        [object]$Body = $null
    )

    if ($MethodName -eq "GET") {
        return Invoke-RestMethod -Method Get -Uri $Url -Headers $Headers
    }

    return Invoke-RestMethod -Method Post -Uri $Url -Headers $Headers -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 20)
}

$apiBase = $BaseUrl.TrimEnd("/")
if (-not $apiBase.EndsWith("/api")) {
    $apiBase = "$apiBase/api"
}

try {
    $decoded = ConvertFrom-Json -InputObject $ParamsJson
    if ($decoded -is [hashtable]) {
        $params = $decoded
    }
    else {
        $params = @{}
        if ($decoded -ne $null) {
            $decoded.PSObject.Properties | ForEach-Object {
                $params[$_.Name] = $_.Value
            }
        }
    }
    if ($params.Keys.Count -eq 0 -and $ParamsJson.Trim() -ne "{}") {
        throw "ParamsJson must decode to a non-null JSON object."
    }
}
catch {
    throw "Invalid ParamsJson: $($_.Exception.Message)"
}

$headers = @{
    Authorization               = "Bearer $Jwt"
    "X-Quoodle-Client-Channel" = "mobile_app"
}

$clientMessageId = "mobile-smoke-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
$dispatchBody = @{
    client_message_id = $clientMessageId
    device_id         = $DeviceId
    method            = $Method
    params            = $params
    sensitive         = [bool]$Sensitive
}
if ($TwoFactorCode.Trim() -ne "") {
    $dispatchBody["two_factor_code"] = $TwoFactorCode.Trim()
}

Write-Stage "Dispatching command '$Method' to device '$DeviceId' via $apiBase/commands"
$dispatch = Invoke-ApiJson -MethodName "POST" -Url "$apiBase/commands" -Headers $headers -Body $dispatchBody

$commandId = [string]($dispatch.command_id)
if ([string]::IsNullOrWhiteSpace($commandId)) {
    throw "Dispatch succeeded without command_id. Raw response: $($dispatch | ConvertTo-Json -Depth 20)"
}

Write-Stage "Accepted command_id=$commandId state=$($dispatch.state)"

$terminalStates = @("completed", "failed", "expired", "rejected")
$deadline = (Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)
$lastState = ""

while ((Get-Date).ToUniversalTime() -lt $deadline) {
    Start-Sleep -Seconds $PollSeconds

    $cmd = Invoke-ApiJson -MethodName "GET" -Url "$apiBase/commands/$commandId" -Headers $headers
    $state = [string]($cmd.state)
    $execState = [string]($cmd.execution_state)
    $origin = [string]($cmd.origin_channel)
    $reason = [string]($cmd.reason)
    $resultStatus = [string]($cmd.result_status)

    if ($state -ne $lastState) {
        Write-Stage "state=$state execution_state=$execState origin_channel=$origin result_status=$resultStatus reason=$reason"
        $lastState = $state
    }

    if ($terminalStates -contains $state) {
        Write-Stage "Terminal state reached: $state"
        Write-Output ($cmd | ConvertTo-Json -Depth 30)

        if ($state -eq "completed") {
            if ($origin -ne "mobile_app") {
                throw "Command completed but origin_channel is '$origin' (expected mobile_app)."
            }
            Write-Stage "PASS: mobile command path executed successfully."
            exit 0
        }

        throw "Command ended in non-success terminal state '$state'."
    }
}

throw "Timed out waiting for terminal state after $TimeoutSeconds seconds."
