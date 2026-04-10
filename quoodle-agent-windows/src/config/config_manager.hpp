#pragma once

#include <cstdlib>
#include <cctype>
#include <string>
#include <fstream>
#include <filesystem>
#include <random>
#include <sstream>
#include "config.hpp"

namespace detail
{
    inline bool ParseBool(const std::string &raw, bool default_value)
    {
        if (raw.empty())
        {
            return default_value;
        }
        std::string lowered(raw);
        for (char &ch : lowered)
        {
            ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
        }
        if (lowered == "1" || lowered == "true" || lowered == "yes" || lowered == "on")
        {
            return true;
        }
        if (lowered == "0" || lowered == "false" || lowered == "no" || lowered == "off")
        {
            return false;
        }
        return default_value;
    }

    inline std::string ReadFileTrim(const std::filesystem::path &path)
    {
        std::ifstream file(path);
        if (!file)
            return {};
        std::string value;
        std::getline(file, value);
        while (!value.empty() && (value.back() == '\n' || value.back() == '\r' || value.back() == ' ' || value.back() == '\t'))
        {
            value.pop_back();
        }
        return value;
    }

    inline std::string GenerateUuid()
    {
        // Windows: use random_device for UUID-like string
        std::random_device rd;
        std::stringstream ss;
        ss << std::hex;
        for (int i = 0; i < 4; ++i)
            ss << rd();
        return ss.str();
    }

    inline std::string GetOrCreateIdentity(const char *env_name, const char *file_env_name, const std::filesystem::path &default_path)
    {
        if (const char *env_value = std::getenv(env_name))
        {
            if (*env_value)
                return env_value;
        }
        const char *path_env = std::getenv(file_env_name);
        std::filesystem::path path = (path_env && *path_env) ? std::filesystem::path(path_env) : default_path;
        auto existing = ReadFileTrim(path);
        if (!existing.empty())
            return existing;
        std::string generated = GenerateUuid();
        std::filesystem::create_directories(path.parent_path());
        std::ofstream out(path, std::ios::trunc);
        if (!out)
            throw std::runtime_error("Unable to write identity file: " + path.string());
        out << generated << "\n";
        return generated;
    }
} // namespace detail

struct ConfigManager
{
    static AgentConfig load_from_env()
    {
        AgentConfig cfg;

        // Core settings
        if (const char *val = std::getenv("AGENT_ENDPOINT"))
            cfg.endpoint = val;
        // Persistent device identity logic
        cfg.device_id = detail::GetOrCreateIdentity(
            "AGENT_DEVICE_ID",
            "AGENT_DEVICE_ID_FILE",
            "C:/ProgramData/Quoodle/device_id");
        if (const char *val = std::getenv("AGENT_JWT"))
            cfg.jwt = val;

        // Reconnection settings
        if (const char *val = std::getenv("AGENT_RECONNECT_INITIAL_DELAY_MS"))
            cfg.reconnection.initial_delay_ms = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_RECONNECT_MAX_DELAY_MS"))
            cfg.reconnection.max_delay_ms = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_RECONNECT_MULTIPLIER"))
            cfg.reconnection.backoff_multiplier = std::stod(val);
        if (const char *val = std::getenv("AGENT_RECONNECT_MAX_RETRIES"))
            cfg.reconnection.max_retries = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_RECONNECT_JITTER"))
            cfg.reconnection.jitter_factor = std::stod(val);

        // Connection settings
        if (const char *val = std::getenv("AGENT_HEARTBEAT_INTERVAL_S"))
            cfg.heartbeat_interval_s = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_TELEMETRY_INTERVAL_S"))
            cfg.telemetry_interval_s = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_TELEMETRY_HTTP_FALLBACK"))
            cfg.telemetry_http_fallback = detail::ParseBool(val, cfg.telemetry_http_fallback);
        if (const char *val = std::getenv("AGENT_TELEMETRY_FALLBACK_URL"))
            cfg.telemetry_fallback_url = val;
        if (const char *val = std::getenv("AGENT_TELEMETRY_QUEUE_DB_PATH"))
            cfg.telemetry_queue_db_path = val;
        if (const char *val = std::getenv("AGENT_TELEMETRY_BATCH_SIZE"))
            cfg.telemetry_batch_size = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_TELEMETRY_MAX_QUEUE_ITEMS"))
            cfg.telemetry_max_queue_items = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_TELEMETRY_RETRY_BACKOFF_S"))
            cfg.telemetry_retry_backoff_s = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_TELEMETRY_RETRY_BACKOFF_MAX_S"))
            cfg.telemetry_retry_backoff_max_s = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_CONNECTION_TIMEOUT_MS"))
            cfg.connection_timeout_ms = static_cast<std::uint32_t>(std::stoul(val));

        return cfg;
    }
};
