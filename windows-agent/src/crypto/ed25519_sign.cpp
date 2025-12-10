#include "ed25519_sign.hpp"
#include <sstream>
#include <functional>

std::string ed25519_sign_payload(const std::string& payload) {
    std::hash<std::string> hasher;
    std::ostringstream oss;
    oss << std::hex << hasher(payload);
    return oss.str();
}
