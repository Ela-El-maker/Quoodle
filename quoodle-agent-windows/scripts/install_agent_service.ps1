param(
    [string]$ExePath = "$PSScriptRoot\\..\\build\\Release\\agent.exe",
    [string]$ServiceName = "QuoodleAgent",
    [string]$DisplayName = "Quoodle Agent",
    [string]$Description = "Quoodle endpoint agent service",
    [string]$StartType = "auto",
    [switch]$DelayedAutoStart,
    [int]$RestartDelayMs = 5000
)

if (!(Test-Path $ExePath)) {
    Write-Host "Agent executable not found: $ExePath"
    exit 1
}

sc.exe stop $ServiceName | Out-Null
sc.exe delete $ServiceName | Out-Null

$quotedBin = '"' + $ExePath + '" --service'
sc.exe create $ServiceName type= own start= $StartType obj= LocalSystem binPath= $quotedBin DisplayName= '"'$DisplayName'"' | Out-Null
if ($DelayedAutoStart) {
    sc.exe config $ServiceName start= delayed-auto | Out-Null
}

# Service recovery: always restart on crash/abnormal stop.
$restartActions = "restart/$RestartDelayMs/restart/$RestartDelayMs/restart/$RestartDelayMs"
sc.exe failure $ServiceName reset= 86400 actions= $restartActions | Out-Null
sc.exe failureflag $ServiceName 1 | Out-Null

sc.exe description $ServiceName $Description | Out-Null
sc.exe start $ServiceName

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
