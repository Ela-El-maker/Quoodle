#include "json_canonicalizer.hpp"

#include <sstream>
#include <iomanip>
namespace utils {

std::string escape_json(const std::string& input) {
    std::ostringstream oss;
    for (char c : input) {
        switch (c) {
            case '\"': oss << "\\\""; break;
            case '\\': oss << "\\\\"; break;
            case '\b': oss << "\\b"; break;
            case '\f': oss << "\\f"; break;
            case '\n': oss << "\\n"; break;
            case '\r': oss << "\\r"; break;
            case '\t': oss << "\\t"; break;
            default:
              if (static_cast<unsigned char>(c) < 0x20)
              {
                oss << "\\u"
                    << std::hex << std::setw(4) << std::setfill('0') << std::uppercase
                    << static_cast<int>(c);
              }
              else
              {
                oss << c;
              }
                break;
        }
    }
    return oss.str();
}

std::string canonical_object(const std::vector<std::pair<std::string, std::string>>& ordered_fields) {
    std::ostringstream oss;
    oss << "{";
    bool first = true;
    for (const auto& kv : ordered_fields) {
        if (!first) {
            oss << ",";
        }
        first = false;
        oss << "\"" << kv.first << "\":" << kv.second;
    }
    oss << "}";
    return oss.str();
}

}  // namespace utils
