#pragma once

#include <string>

namespace quoodle {

// JCS canonicalization placeholder. Implement RFC 8785 before production use.
std::string CanonicalizeJcs(const std::string &json);

}  // namespace quoodle
