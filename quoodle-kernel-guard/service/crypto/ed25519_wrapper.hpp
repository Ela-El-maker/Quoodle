#pragma once

#include <string>

// Returns a base64-encoded detached Ed25519 signature for the given message.
// If Ed25519 support is not available at build time, returns an empty string.
std::string ed25519_sign_message(const std::string &message);
