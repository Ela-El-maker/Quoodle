#pragma once

#include <string>
#include <vector>

namespace validation {

struct ValidationError {
    std::string field;
    std::string message;
};

bool validate_request_schema(const std::string& opcode, const std::string& payload, std::vector<ValidationError>& errors);

}  // namespace validation
