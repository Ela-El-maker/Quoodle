#pragma once

#include <cstdint>
#include <string>

struct TelemetryHttpResponse
{
    bool ok{false};
    int status_code{0};
    std::string body;
    std::string error_reason;
};

class TelemetryHttpClient
{
public:
    TelemetryHttpResponse post_json(
        const std::string &url,
        const std::string &bearer_jwt,
        const std::string &body_json,
        std::uint32_t timeout_ms = 10000) const;
};
