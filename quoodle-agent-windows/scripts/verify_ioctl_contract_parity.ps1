param(
    [string]$AgentHeaderPath = "",
    [string]$KernelHeaderPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AgentHeaderPath)) {
    $AgentHeaderPath = Join-Path $PSScriptRoot "..\src\kernel\driver_ioctl.hpp"
}
if ([string]::IsNullOrWhiteSpace($KernelHeaderPath)) {
    $KernelHeaderPath = Join-Path $PSScriptRoot "..\..\quoodle-kernel-guard\driver\quoodle_ioctl.h"
}

$agentHeader = (Resolve-Path $AgentHeaderPath).Path
$kernelHeader = (Resolve-Path $KernelHeaderPath).Path

function Read-DefineMap {
    param([string]$Path)
    $map = @{}
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*#define\s+([A-Za-z0-9_]+)\s+([0-9A-Za-zx]+)\s*$') {
            $map[$matches[1]] = $matches[2]
        }
    }
    return $map
}

$agentDefs = Read-DefineMap -Path $agentHeader
$kernelDefs = Read-DefineMap -Path $kernelHeader

$keysToMatch = @(
    "QUOODLE_IOCTL_VERSION",
    "QUOODLE_MAX_RESULT",
    "QUOODLE_MAX_PARAMS",
    "QUOODLE_MAX_REQUEST_ID",
    "QUOODLE_MAX_COMMAND_ID",
    "QUOODLE_MAX_POLICY_HASH",
    "QERR_COLLECT_INFO_FAILED",
    "QERR_COLLECT_INFO_PAYLOAD_TOO_LARGE"
)

$mismatches = @()
foreach ($key in $keysToMatch) {
    $agentValue = $agentDefs[$key]
    $kernelValue = $kernelDefs[$key]
    if ($agentValue -ne $kernelValue) {
        $mismatches += [PSCustomObject]@{
            Name = $key
            Agent = $agentValue
            Kernel = $kernelValue
        }
    }
}

if ($mismatches.Count -gt 0) {
    Write-Host "IOCTL contract parity check FAILED:" -ForegroundColor Red
    $mismatches | Format-Table -AutoSize
    exit 1
}

Write-Host "IOCTL contract parity check PASS" -ForegroundColor Green
foreach ($key in $keysToMatch) {
    Write-Host ("{0}={1}" -f $key, $agentDefs[$key])
}
exit 0
