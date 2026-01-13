# run_e2e_signature_test.ps1
#
# Task 1.7: Script to generate ephemeral Ed25519 keys and run the E2E signature chain test.
#
# This script:
#   1. Generates an Agent key pair
#   2. Generates a Kernel key pair
#   3. Sets environment variables
#   4. Runs the e2e_signature_chain_test
#
# Usage:
#   .\run_e2e_signature_test.ps1 [-TestBinary <path>]
#
# Requirements:
#   - Python with cryptography library

param(
    [string]$TestBinary = ".\build\Release\e2e_signature_chain_test.exe"
)

Write-Host "=== E2E Signature Chain Test Runner ===" -ForegroundColor Cyan
Write-Host ""

# Check if test binary exists
if (-not (Test-Path $TestBinary)) {
    # Try Debug build
    $DebugBinary = $TestBinary -replace "Release", "Debug"
    if (Test-Path $DebugBinary) {
        $TestBinary = $DebugBinary
    }
    else {
        Write-Host "Test binary not found: $TestBinary" -ForegroundColor Red
        Write-Host "Please build the project first with: cmake --build build --config Release" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Using test binary: $TestBinary" -ForegroundColor Green

# Generate keys using Python
Write-Host "Generating ephemeral Ed25519 key pairs..." -ForegroundColor Yellow

$pythonScript = @'
import base64
try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization

    # Generate Agent keypair
    agent_key = Ed25519PrivateKey.generate()
    agent_pk = agent_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw
    )
    agent_sk = agent_key.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption()
    )
    agent_sk_full = agent_sk + agent_pk

    # Generate Kernel keypair
    kernel_key = Ed25519PrivateKey.generate()
    kernel_pk = kernel_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw
    )
    kernel_sk = kernel_key.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption()
    )
    kernel_sk_full = kernel_sk + kernel_pk

    # Output as JSON for PowerShell to parse
    import json
    print(json.dumps({
        "agent_sk": base64.b64encode(agent_sk_full).decode(),
        "agent_pk": base64.b64encode(agent_pk).decode(),
        "kernel_sk": base64.b64encode(kernel_sk_full).decode(),
        "kernel_pk": base64.b64encode(kernel_pk).decode()
    }))
except ImportError as e:
    print(f'{{"error": "cryptography library not installed: {e}"}}')
    exit(1)
except Exception as e:
    print(f'{{"error": "{e}"}}')
    exit(1)
'@

try {
    $keysJson = python -c $pythonScript 2>&1
    $keys = $keysJson | ConvertFrom-Json
    
    if ($keys.error) {
        Write-Host "ERROR: $($keys.error)" -ForegroundColor Red
        Write-Host "Please install: pip install cryptography" -ForegroundColor Yellow
        exit 1
    }
}
catch {
    Write-Host "ERROR: Failed to generate keys. Make sure Python is installed with cryptography library." -ForegroundColor Red
    Write-Host "Install with: pip install cryptography" -ForegroundColor Yellow
    Write-Host "Error details: $_" -ForegroundColor Red
    exit 1
}

Write-Host "Keys generated successfully." -ForegroundColor Green
Write-Host ""

# Set environment variables
$env:CI_AGENT_SK_B64 = $keys.agent_sk
$env:CI_AGENT_PK_B64 = $keys.agent_pk
$env:CI_KERNEL_SK_B64 = $keys.kernel_sk
$env:CI_KERNEL_PK_B64 = $keys.kernel_pk

Write-Host "Environment variables set:" -ForegroundColor Cyan
Write-Host "  CI_AGENT_SK_B64: $($keys.agent_sk.Substring(0, 20))..." -ForegroundColor Gray
Write-Host "  CI_AGENT_PK_B64: $($keys.agent_pk)" -ForegroundColor Gray
Write-Host "  CI_KERNEL_SK_B64: $($keys.kernel_sk.Substring(0, 20))..." -ForegroundColor Gray
Write-Host "  CI_KERNEL_PK_B64: $($keys.kernel_pk)" -ForegroundColor Gray
Write-Host ""

# Run the test
Write-Host "Running E2E signature chain test..." -ForegroundColor Yellow
Write-Host "-----------------------------------" -ForegroundColor Gray

& $TestBinary
$exitCode = $LASTEXITCODE

Write-Host "-----------------------------------" -ForegroundColor Gray

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "✓ E2E Signature Chain Test PASSED" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "✗ E2E Signature Chain Test FAILED (exit code: $exitCode)" -ForegroundColor Red
}

exit $exitCode
