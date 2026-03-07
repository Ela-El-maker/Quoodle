#pragma once

#include <string>

namespace quoodle {

// Canonicalize JSON according to JCS (RFC 8785).
std::string CanonicalizeJcs(const std::string &json);

}  // namespace quoodle
