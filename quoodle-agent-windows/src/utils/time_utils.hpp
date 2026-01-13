#pragma once

#include <string>
#include <chrono>
#include <ctime>
#include <cstdio>

namespace utils
{

    /**
     * Returns the current UTC timestamp in ISO 8601 format.
     * Format: "2026-01-13T12:00:00Z"
     */
    inline std::string iso_timestamp()
    {
        using namespace std::chrono;
        auto now = system_clock::now();
        std::time_t t = system_clock::to_time_t(now);
        std::tm tm{};
#ifdef _WIN32
        gmtime_s(&tm, &t);
#else
        gmtime_r(&t, &tm);
#endif
        char buffer[64];
        std::snprintf(buffer, sizeof(buffer), "%04d-%02d-%02dT%02d:%02d:%02dZ",
                      tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
                      tm.tm_hour, tm.tm_min, tm.tm_sec);
        return std::string(buffer);
    }

} // namespace utils
