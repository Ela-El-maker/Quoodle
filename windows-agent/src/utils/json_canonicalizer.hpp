#pragma once

#include <string>
#include <vector>
#include <utility>

namespace utils {

std::string escape_json(const std::string& input);

std::string canonical_object(const std::vector<std::pair<std::string, std::string>>& ordered_fields);

}  // namespace utils
