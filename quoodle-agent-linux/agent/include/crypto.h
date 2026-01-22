#pragma once

#include <string>

namespace quoodle {

// Ed25519 signing placeholder. Implement with libsodium before production use.
std::string SignEd25519(const std::string &priv_b64, const std::string &message);
bool VerifyEd25519(const std::string &pub_b64, const std::string &message, const std::string &sig_b64);

}  // namespace quoodle
