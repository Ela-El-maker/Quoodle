#!/bin/bash
# run_e2e_signature_test.sh
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
#   ./run_e2e_signature_test.sh [path_to_test_binary]
#
# Requirements:
#   - openssl with Ed25519 support
#   - OR Python with cryptography library

set -e

TEST_BINARY="${1:-./build/e2e_signature_chain_test}"

echo "=== E2E Signature Chain Test Runner ==="
echo ""

# Check if test binary exists
if [ ! -f "$TEST_BINARY" ] && [ ! -f "${TEST_BINARY}.exe" ]; then
    echo "Test binary not found: $TEST_BINARY"
    echo "Please build the project first with: cmake --build build"
    exit 1
fi

# Try to generate keys using Python (more portable)
generate_keys_python() {
    python3 << 'EOF'
import os
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
    # Ed25519 private key is seed || public_key (64 bytes total)
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

    # Output as shell exports
    print(f"export CI_AGENT_SK_B64='{base64.b64encode(agent_sk_full).decode()}'")
    print(f"export CI_AGENT_PK_B64='{base64.b64encode(agent_pk).decode()}'")
    print(f"export CI_KERNEL_SK_B64='{base64.b64encode(kernel_sk_full).decode()}'")
    print(f"export CI_KERNEL_PK_B64='{base64.b64encode(kernel_pk).decode()}'")
except ImportError:
    print("# Python cryptography library not available")
    exit(1)
EOF
}

# Try to generate keys using OpenSSL
generate_keys_openssl() {
    # Generate Agent keypair
    AGENT_KEY=$(openssl genpkey -algorithm Ed25519 2>/dev/null)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    AGENT_SK=$(echo "$AGENT_KEY" | openssl pkey -outform DER 2>/dev/null | tail -c 64 | base64 -w0)
    AGENT_PK=$(echo "$AGENT_KEY" | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 | base64 -w0)
    
    # Generate Kernel keypair
    KERNEL_KEY=$(openssl genpkey -algorithm Ed25519 2>/dev/null)
    KERNEL_SK=$(echo "$KERNEL_KEY" | openssl pkey -outform DER 2>/dev/null | tail -c 64 | base64 -w0)
    KERNEL_PK=$(echo "$KERNEL_KEY" | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 | base64 -w0)
    
    echo "export CI_AGENT_SK_B64='$AGENT_SK'"
    echo "export CI_AGENT_PK_B64='$AGENT_PK'"
    echo "export CI_KERNEL_SK_B64='$KERNEL_SK'"
    echo "export CI_KERNEL_PK_B64='$KERNEL_PK'"
}

echo "Generating ephemeral Ed25519 key pairs..."

# Try Python first, then OpenSSL
KEYS=$(generate_keys_python 2>/dev/null) || KEYS=$(generate_keys_openssl 2>/dev/null) || {
    echo "ERROR: Failed to generate Ed25519 keys."
    echo "Please install Python with cryptography library or OpenSSL with Ed25519 support."
    exit 1
}

echo "Keys generated successfully."
echo ""

# Export the keys
eval "$KEYS"

# Verify keys are set
if [ -z "$CI_AGENT_SK_B64" ]; then
    echo "ERROR: Failed to set CI_AGENT_SK_B64"
    exit 1
fi

echo "Environment variables set:"
echo "  CI_AGENT_SK_B64: ${CI_AGENT_SK_B64:0:20}..."
echo "  CI_AGENT_PK_B64: $CI_AGENT_PK_B64"
echo "  CI_KERNEL_SK_B64: ${CI_KERNEL_SK_B64:0:20}..."
echo "  CI_KERNEL_PK_B64: $CI_KERNEL_PK_B64"
echo ""

# Run the test
echo "Running E2E signature chain test..."
echo "-----------------------------------"

if [ -f "${TEST_BINARY}.exe" ]; then
    "${TEST_BINARY}.exe"
else
    "$TEST_BINARY"
fi

EXIT_CODE=$?

echo "-----------------------------------"

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✓ E2E Signature Chain Test PASSED"
else
    echo ""
    echo "✗ E2E Signature Chain Test FAILED (exit code: $EXIT_CODE)"
fi

exit $EXIT_CODE
