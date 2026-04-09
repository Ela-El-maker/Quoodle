param(
    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",
    [ValidateSet("x64", "ARM64")]
    [string]$Platform = "x64",
    [string]$ProjectPath = "$PSScriptRoot\..\driver\kmdf\quoodle_kmdf\quoodle_kmdf.vcxproj",
    [switch]$CleanIntermediate = $true,
    [switch]$SkipPackageVerification = $true,
    [switch]$DisableTestSign = $true,
    [switch]$DisableApiValidator = $true,
    [switch]$DisableInf2Cat = $true
)

$ErrorActionPreference = "Stop"

function Resolve-MsBuildPath {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $candidate = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" 2>$null | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    $cmd = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    throw "MSBuild not found. Install Visual Studio 2026 Build Tools (Desktop + WDK tooling) or open a Developer PowerShell."
}

function Resolve-DriverOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectDir,
        [Parameter(Mandatory = $true)]
        [string]$ConfigurationName,
        [Parameter(Mandatory = $true)]
        [string]$PlatformName
    )

    $candidates = @(
        (Join-Path $ProjectDir "..\$PlatformName\$ConfigurationName\quoodle_kmdf.sys"),
        (Join-Path $ProjectDir "quoodle_kmdf\$PlatformName\$ConfigurationName\quoodle_kmdf.sys"),
        (Join-Path $ProjectDir "$PlatformName\$ConfigurationName\quoodle_kmdf.sys")
    )

    foreach ($candidate in $candidates) {
        $resolved = [System.IO.Path]::GetFullPath($candidate)
        if (Test-Path $resolved) {
            return $resolved
        }
    }

    return $null
}

function Resolve-MsBuildVersionOverride {
    $wdkBin = "C:\Program Files (x86)\Windows Kits\10\build\10.0.26100.0\bin"
    $vs18Tasks = Join-Path $wdkBin "Microsoft.DriverKit.Build.Tasks.18.0.dll"
    $vs17Tasks = Join-Path $wdkBin "Microsoft.DriverKit.Build.Tasks.17.0.dll"

    if ((-not (Test-Path $vs18Tasks)) -and (Test-Path $vs17Tasks)) {
        return "17.0"
    }

    return $null
}

function Clear-StaleBuildState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectDir,
        [Parameter(Mandatory = $true)]
        [string]$ConfigurationName,
        [Parameter(Mandatory = $true)]
        [string]$PlatformName
    )

    $stalePaths = @(
        (Join-Path $ProjectDir "quoodle_kmdf\$PlatformName\$ConfigurationName"),
        (Join-Path $ProjectDir "..\$PlatformName\$ConfigurationName\quoodle_kmdf\quoodle_kmdf.inf"),
        (Join-Path $ProjectDir "..\$PlatformName\$ConfigurationName\quoodle_kmdf\quoodle_kmdf.sys")
    )

    foreach ($path in $stalePaths) {
        $resolved = [System.IO.Path]::GetFullPath($path)
        if (Test-Path $resolved) {
            try {
                Remove-Item -Recurse -Force -LiteralPath $resolved -ErrorAction Stop
                Write-Host "Removed stale build state: $resolved"
            } catch {
                Write-Warning "Could not remove stale build state '$resolved': $($_.Exception.Message)"
            }
        }
    }
}

$resolvedProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if (-not (Test-Path $resolvedProjectPath)) {
    throw "KMDF project not found: $resolvedProjectPath"
}

$projectDir = Split-Path -Parent $resolvedProjectPath
$msbuildPath = Resolve-MsBuildPath
$vsVersionOverride = Resolve-MsBuildVersionOverride

Write-Host "Using MSBuild: $msbuildPath"
Write-Host "Building: $resolvedProjectPath"
Write-Host "Config: $Configuration | Platform: $Platform"

if ($CleanIntermediate) {
    Clear-StaleBuildState -ProjectDir $projectDir -ConfigurationName $Configuration -PlatformName $Platform
}

$msbuildArgs = @(
    $resolvedProjectPath,
    "/m",
    "/nologo",
    "/p:Configuration=$Configuration",
    "/p:Platform=$Platform"
)

if ($SkipPackageVerification) {
    $msbuildArgs += "/p:SkipPackageVerification=true"
}

if ($DisableTestSign) {
    $msbuildArgs += "/p:EnableTestSign=false"
}

if ($DisableApiValidator) {
    $msbuildArgs += "/p:ApiValidator_Enable=false"
}

if ($DisableInf2Cat) {
    $msbuildArgs += "/p:EnableInf2cat=false"
}

if (-not [string]::IsNullOrWhiteSpace($vsVersionOverride)) {
    Write-Host "WDK build tasks for VS 18.0 are missing; forcing VisualStudioVersion=$vsVersionOverride for compatibility."
    $msbuildArgs += "/p:VisualStudioVersion=$vsVersionOverride"
}

& $msbuildPath @msbuildArgs

if ($LASTEXITCODE -ne 0) {
    throw "Driver build failed with exit code $LASTEXITCODE."
}

$builtDriver = Resolve-DriverOutput -ProjectDir $projectDir -ConfigurationName $Configuration -PlatformName $Platform
if (-not $builtDriver) {
    throw "Build finished but quoodle_kmdf.sys was not found in expected output folders."
}

$canonicalOutDir = [System.IO.Path]::GetFullPath((Join-Path $projectDir "..\$Platform\$Configuration"))
$canonicalDriver = Join-Path $canonicalOutDir "quoodle_kmdf.sys"
New-Item -ItemType Directory -Force -Path $canonicalOutDir | Out-Null
if ([System.StringComparer]::OrdinalIgnoreCase.Equals($builtDriver, $canonicalDriver)) {
    Write-Host "Build output already matches canonical path."
} else {
    Copy-Item -Force $builtDriver $canonicalDriver
}

Write-Host "Build succeeded."
Write-Host "Built artifact:    $builtDriver"
Write-Host "Canonical artifact: $canonicalDriver"

try {
    $sig = Get-AuthenticodeSignature -FilePath $canonicalDriver
    Write-Host "Driver signature: $($sig.Status)"
    if ($sig.Status -eq "NotSigned") {
        Write-Warning "Driver is unsigned. For loadable local dev driver builds, rebuild with test-sign enabled:"
        Write-Warning ".\scripts\build_driver.ps1 -Configuration $Configuration -Platform $Platform -DisableTestSign:`$false"
    } elseif ($sig.Status -eq "UnknownError" -and $sig.StatusMessage -match "not trusted") {
        $thumbprint = if ($sig.SignerCertificate) { $sig.SignerCertificate.Thumbprint } else { "<unknown>" }
        Write-Warning "Driver is signed but the certificate chain is not trusted on this machine (thumbprint: $thumbprint)."
        Write-Warning "Import the signer certificate into LocalMachine\\Root and LocalMachine\\TrustedPublisher before starting the service."
    }
} catch {
    Write-Warning "Could not inspect driver signature: $($_.Exception.Message)"
}
