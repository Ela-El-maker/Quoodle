#pragma once

#include <string>

namespace crypto
{

    /**
     * Verify a base64-encoded Ed25519 signature against a message.
     *
     * @param message The original message that was signed
     * @param sig_b64 Base64-encoded signature (64 bytes decoded)
     * @param pubkey_b64 Base64-encoded public key (32 bytes decoded). If empty,
     *                   attempts to load from environment variables:
     *                   - CONTROLLER_PUBKEY_B64
     *                   - CONTROLLER_PUBKEY_DPAPI_B64 / CONTROLLER_PUBKEY_DPAPI_PATH (DPAPI protected)
     *                   - CONTROLLER_PUBKEY_PATH (file path)
     * @return true if signature is valid, false otherwise
     */
    bool ed25519_verify_message(const std::string &message, const std::string &sig_b64, const std::string &pubkey_b64 = "");

} // namespace crypto
