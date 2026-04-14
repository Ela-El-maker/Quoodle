param(
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

& "$PSScriptRoot\unblock-app.ps1" -Basename "whatsapp.root.exe" -Jwt $Jwt -BaseUrl $BaseUrl
& "$PSScriptRoot\unblock-app.ps1" -Basename "whatsapp.exe" -Jwt $Jwt -BaseUrl $BaseUrl
