#include "json_canonicalizer.hpp"

#include <sstream>
#include <iomanip>

namespace utils
{

    std::string escape_json(const std::string &input)
    {
        std::ostringstream oss;
        for (unsigned char uc : input)
        {
            char c = static_cast<char>(uc);
            switch (c)
            {
            case '"':
                oss << "\\\"";
                break;
            case '\\':
                oss << "\\\\";
                break;
            case '\b':
                oss << "\\b";
                break;
            case '\f':
                oss << "\\f";
                break;
            case '\n':
                oss << "\\n";
                break;
            case '\r':
                oss << "\\r";
                break;
            case '\t':
                oss << "\\t";
                break;
            default:
                if (uc < 0x20)
                {
                    oss << "\\u"
                        << std::hex << std::setw(4) << std::setfill('0') << std::uppercase
                        << static_cast<int>(uc);
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

    std::string canonical_object(const std::vector<std::pair<std::string, std::string>> &ordered_fields)
    {
        std::ostringstream oss;
        oss << "{";
        bool first = true;
        for (const auto &kv : ordered_fields)
        {
            if (!first)
                oss << ",";
            first = false;
            oss << "\"" << kv.first << "\":" << kv.second;
        }
        oss << "}";
        return oss.str();
    }

} // namespace utils
