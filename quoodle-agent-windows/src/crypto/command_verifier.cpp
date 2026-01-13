#include "command_verifier.hpp"
#include "ed25519_verify.hpp"
#include "json_canonicalizer.hpp"
#include "../logging/logger.hpp"

#include <nlohmann/json.hpp>
#include <chrono>
#include <ctime>
#include <sstream>
#include <iomanip>
#include <algorithm>

namespace crypto
{

    // Forward declaration for internal helper
    static std::string build_canonical_value(const nlohmann::json &value);

    std::int64_t parse_iso8601_to_epoch(const std::string &timestamp)
    {
        // Expected format: "2026-01-13T12:00:00Z"
        std::tm tm{};
        std::istringstream ss(timestamp);
        ss >> std::get_time(&tm, "%Y-%m-%dT%H:%M:%S");
        if (ss.fail())
        {
            return 0;
        }

#ifdef _WIN32
        // Use _mkgmtime on Windows for UTC
        return static_cast<std::int64_t>(_mkgmtime(&tm));
#else
        // Use timegm on POSIX systems for UTC
        return static_cast<std::int64_t>(timegm(&tm));
#endif
    }

    bool check_ttl(const std::string &timestamp_iso8601, int ttl_seconds)
    {
        auto envelope_time = parse_iso8601_to_epoch(timestamp_iso8601);
        if (envelope_time == 0)
        {
            Logger::log(LogLevel::Error, "check_ttl: failed to parse timestamp");
            return false;
        }

        auto now = std::chrono::system_clock::now();
        auto now_epoch = std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch()).count();

        auto expiry = envelope_time + ttl_seconds;
        return now_epoch <= expiry;
    }

    /**
     * Recursively build canonical JSON value representation.
     */
    static std::string build_canonical_value(const nlohmann::json &value)
    {
        if (value.is_null())
        {
            return "null";
        }
        else if (value.is_boolean())
        {
            return value.get<bool>() ? "true" : "false";
        }
        else if (value.is_number_integer())
        {
            return std::to_string(value.get<std::int64_t>());
        }
        else if (value.is_number_unsigned())
        {
            return std::to_string(value.get<std::uint64_t>());
        }
        else if (value.is_number_float())
        {
            std::ostringstream oss;
            oss << std::setprecision(17) << value.get<double>();
            return oss.str();
        }
        else if (value.is_string())
        {
            return "\"" + escape_json(value.get<std::string>()) + "\"";
        }
        else if (value.is_array())
        {
            std::ostringstream oss;
            oss << "[";
            bool first = true;
            for (const auto &elem : value)
            {
                if (!first)
                    oss << ",";
                first = false;
                oss << build_canonical_value(elem);
            }
            oss << "]";
            return oss.str();
        }
        else if (value.is_object())
        {
            // Get all keys and sort lexicographically
            std::vector<std::string> keys;
            for (auto it = value.begin(); it != value.end(); ++it)
            {
                keys.push_back(it.key());
            }
            std::sort(keys.begin(), keys.end());

            std::ostringstream oss;
            oss << "{";
            bool first = true;
            for (const auto &key : keys)
            {
                if (!first)
                    oss << ",";
                first = false;
                oss << "\"" << key << "\":" << build_canonical_value(value[key]);
            }
            oss << "}";
            return oss.str();
        }
        return "";
    }

    std::string build_canonical_envelope(const std::string &envelope_json)
    {
        try
        {
            auto envelope = nlohmann::json::parse(envelope_json);

            // Remove the 'sig' field for canonical representation
            if (envelope.contains("sig"))
            {
                envelope.erase("sig");
            }

            return build_canonical_value(envelope);
        }
        catch (const std::exception &e)
        {
            Logger::log(LogLevel::Error, std::string("build_canonical_envelope: parse error: ") + e.what());
            return "";
        }
    }

    VerificationResult verify_command_envelope(const std::string &envelope_json,
                                               std::uint64_t last_seq,
                                               const std::string &controller_pubkey_b64)
    {
        VerificationResult result;

        try
        {
            auto envelope = nlohmann::json::parse(envelope_json);

            // Extract signature
            std::string sig = envelope.value("sig", "");
            if (sig.empty())
            {
                result.error_code = "SIGNATURE_MISSING";
                result.error_message = "Command envelope has no signature";
                return result;
            }

            // Extract sequence for replay protection
            std::uint64_t seq = envelope.value("seq", static_cast<std::uint64_t>(0));
            if (seq <= last_seq)
            {
                result.error_code = "SEQ_REPLAY";
                result.error_message = "Sequence number indicates replay attack: got " +
                                       std::to_string(seq) + ", expected > " + std::to_string(last_seq);
                return result;
            }

            // Extract TTL info from header
            if (envelope.contains("header"))
            {
                auto header = envelope["header"];
                std::string timestamp = header.value("timestamp", "");
                int ttl_seconds = header.value("ttl_seconds", 0);

                if (!timestamp.empty() && ttl_seconds > 0)
                {
                    if (!check_ttl(timestamp, ttl_seconds))
                    {
                        result.error_code = "TTL_EXPIRED";
                        result.error_message = "Command envelope TTL has expired";
                        return result;
                    }
                }
            }

            // Build canonical payload for signature verification
            std::string canonical = build_canonical_envelope(envelope_json);
            if (canonical.empty())
            {
                result.error_code = "CANONICAL_BUILD_FAILED";
                result.error_message = "Failed to build canonical envelope";
                return result;
            }

            // Verify signature
            bool sig_valid = ed25519_verify_message(canonical, sig, controller_pubkey_b64);
            if (!sig_valid)
            {
                result.error_code = "SIGNATURE_INVALID";
                result.error_message = "Ed25519 signature verification failed";
                return result;
            }

            // All checks passed
            result.valid = true;
            return result;
        }
        catch (const std::exception &e)
        {
            result.error_code = "PARSE_ERROR";
            result.error_message = std::string("Failed to parse command envelope: ") + e.what();
            return result;
        }
    }

} // namespace crypto
