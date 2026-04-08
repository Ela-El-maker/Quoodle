#pragma once

#include <string>

std::string ed25519_sign_payload(const std::string& payload);
std::string ed25519_active_public_key_b64();
