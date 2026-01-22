#include "jcs.h"

#include <stdexcept>

#include <nlohmann/json.hpp>

namespace {

void EnsureNoFloats(const nlohmann::json &value) {
    if (value.is_number_float()) {
        throw std::runtime_error("JCS: floats are not allowed");
    }
    if (value.is_array()) {
        for (const auto &item : value) {
            EnsureNoFloats(item);
        }
    } else if (value.is_object()) {
        for (const auto &item : value.items()) {
            EnsureNoFloats(item.value());
        }
    }
}

}  // namespace

namespace quoodle {

std::string CanonicalizeJcs(const std::string &json) {
    nlohmann::json parsed = nlohmann::json::parse(json);
    EnsureNoFloats(parsed);
    return parsed.dump();
}

}  // namespace quoodle
