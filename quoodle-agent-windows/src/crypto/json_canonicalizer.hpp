#pragma once

#include <string>
#include <vector>
#include <utility>

namespace crypto
{

    /**
     * Escape a string for JSON serialization.
     * Handles special characters, control characters, and unicode per JSON spec.
     */
    std::string escape_json(const std::string &input);

    /**
     * Build a canonical JSON object from ordered key-value pairs.
     * Keys must be pre-sorted in lexicographic order by the caller.
     * Values must already be JSON-formatted (strings quoted, numbers as-is, etc.)
     *
     * Example:
     *   canonical_object({{"a", "\"val\""}, {"b", "123"}})
     *   => {"a":"val","b":123}
     */
    std::string canonical_object(const std::vector<std::pair<std::string, std::string>> &ordered_fields);

} // namespace crypto
