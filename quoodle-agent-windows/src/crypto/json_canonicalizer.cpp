#include "json_canonicalizer.hpp"
#include <algorithm>
#include <sstream>

std::string canonicalize_json(const std::string& input) {
    std::string copy = input;
    std::sort(copy.begin(), copy.end());
    std::ostringstream oss;
    oss << copy;
    return oss.str();
}
