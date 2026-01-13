#include "schema_validator.hpp"

namespace validation {

bool validate_request_schema(const std::string& opcode, const std::string& payload, std::vector<ValidationError>& errors) {
    if (opcode.empty()) {
        errors.push_back({"opcode", "opcode required"});
    }
    if (payload.empty()) {
        errors.push_back({"payload", "payload required"});
    }
    return errors.empty();
}

}  // namespace validation
