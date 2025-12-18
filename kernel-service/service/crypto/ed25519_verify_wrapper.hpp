#pragma once

#include <string>

// Verify a base64-encoded Ed25519 signature against a message and base64-encoded public key.
// Returns true if signature is valid. If libsodium is not available, returns false.
bool ed25519_verify_message(const std::string &message, const std::string &sig_b64, const std::string &pubkey_b64);
