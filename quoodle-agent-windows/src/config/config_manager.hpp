#pragma once

#include <cstdlib>
#include <cctype>
#include <algorithm>
#include <string>
#include <fstream>
#include <filesystem>
#include <random>
#include <sstream>
#include "config.hpp"

namespace detail
{
    inline bool starts_with(const std::string &value, const std::string &prefix)
    {
        return value.rfind(prefix, 0) == 0;
    }

    inline std::string trim_copy(const std::string &value)
    {
        std::size_t start = 0;
        while (start < value.size() && std::isspace(static_cast<unsigned char>(value[start])))
        {
            ++start;
        }

        std::size_t end = value.size();
        while (end > start && std::isspace(static_cast<unsigned char>(value[end - 1])))
        {
            --end;
        }

        return value.substr(start, end - start);
    }

    inline std::string derive_http_base_from_agent_endpoint(const std::string &endpoint)
    {
        auto value = trim_copy(endpoint);
        if (value.empty())
        {
            return "http://localhost:8000";
        }

        if (starts_with(value, "wss://"))
        {
            value.replace(0, 6, "https://");
        }
        else if (starts_with(value, "ws://"))
        {
            value.replace(0, 5, "http://");
        }

        while (!value.empty() && value.back() == '/')
        {
            value.pop_back();
        }

        const std::string agent_suffix = "/agent";
        if (value.size() >= agent_suffix.size() &&
            value.compare(value.size() - agent_suffix.size(), agent_suffix.size(), agent_suffix) == 0)
        {
            value.erase(value.size() - agent_suffix.size());
        }

        while (!value.empty() && value.back() == '/')
        {
            value.pop_back();
        }

        return value.empty() ? "http://localhost:8000" : value;
    }

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

    inline std::string ReadEnvOrFile(const char *env_name, const char *file_env_name, const std::filesystem::path &default_path)
    {
        if (const char *env_value = std::getenv(env_name))
        {
            if (*env_value)
            {
                return env_value;
            }
        }

        const char *path_env = std::getenv(file_env_name);
        std::filesystem::path path = (path_env && *path_env) ? std::filesystem::path(path_env) : default_path;
        return ReadFileTrim(path);
    }
} // namespace detail

struct ConfigManager
{
    static AgentConfig load_from_env()
    {
        AgentConfig cfg;

        // Core settings
        const std::string endpoint = detail::ReadEnvOrFile(
            "AGENT_ENDPOINT",
            "AGENT_ENDPOINT_FILE",
            "C:/ProgramData/Quoodle/agent_endpoint");
        if (!detail::trim_copy(endpoint).empty())
        {
            cfg.endpoint = endpoint;
        }
        // Persistent device identity logic
        cfg.device_id = detail::GetOrCreateIdentity(
            "AGENT_DEVICE_ID",
            "AGENT_DEVICE_ID_FILE",
            "C:/ProgramData/Quoodle/device_id");
        cfg.jwt = detail::ReadEnvOrFile(
            "AGENT_JWT",
            "AGENT_JWT_FILE",
            "C:/ProgramData/Quoodle/agent_jwt");

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
        if (const char *val = std::getenv("AGENT_ARTIFACT_API_BASE_URL"))
            cfg.artifact_api_base_url = val;
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
        if (const char *val = std::getenv("AGENT_KERNEL_TELEMETRY_TIER"))
            cfg.kernel_telemetry_tier = val;
        if (const char *val = std::getenv("AGENT_KERNEL_TELEMETRY_ENABLE_EXEC"))
            cfg.kernel_enable_exec = detail::ParseBool(val, cfg.kernel_enable_exec);
        if (const char *val = std::getenv("AGENT_KERNEL_TELEMETRY_ENABLE_INTEGRITY"))
            cfg.kernel_enable_integrity = detail::ParseBool(val, cfg.kernel_enable_integrity);
        if (const char *val = std::getenv("AGENT_KERNEL_TELEMETRY_ENABLE_ATTESTATION"))
            cfg.kernel_enable_attestation = detail::ParseBool(val, cfg.kernel_enable_attestation);
        if (const char *val = std::getenv("AGENT_KERNEL_TELEMETRY_ENABLE_UPDATE"))
            cfg.kernel_enable_update = detail::ParseBool(val, cfg.kernel_enable_update);
        if (const char *val = std::getenv("AGENT_KERNEL_TELEMETRY_ENABLE_RUNTIME"))
            cfg.kernel_enable_runtime = detail::ParseBool(val, cfg.kernel_enable_runtime);
        if (const char *val = std::getenv("AGENT_KERNEL_TELEMETRY_SAMPLE_EXEC_PCT"))
            cfg.kernel_sample_exec_pct = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_KERNEL_TELEMETRY_SAMPLE_INTEGRITY_PCT"))
            cfg.kernel_sample_integrity_pct = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_KERNEL_TELEMETRY_SAMPLE_ATTESTATION_PCT"))
            cfg.kernel_sample_attestation_pct = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_KERNEL_TELEMETRY_SAMPLE_UPDATE_PCT"))
            cfg.kernel_sample_update_pct = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_KERNEL_TELEMETRY_SAMPLE_RUNTIME_PCT"))
            cfg.kernel_sample_runtime_pct = static_cast<std::uint32_t>(std::stoul(val));
        if (const char *val = std::getenv("AGENT_KERNEL_TELEMETRY_ALLOW_RAW_SENSITIVE"))
            cfg.kernel_allow_raw_sensitive = detail::ParseBool(val, cfg.kernel_allow_raw_sensitive);
        if (const char *val = std::getenv("AGENT_CONNECTION_TIMEOUT_MS"))
            cfg.connection_timeout_ms = static_cast<std::uint32_t>(std::stoul(val));

        std::string tier = cfg.kernel_telemetry_tier;
        std::transform(tier.begin(), tier.end(), tier.begin(), [](unsigned char ch)
                       { return static_cast<char>(std::tolower(ch)); });
        if (tier == "balanced")
        {
            cfg.kernel_enable_integrity = true;
            cfg.kernel_enable_attestation = true;
        }
        else if (tier == "deep")
        {
            cfg.kernel_enable_integrity = true;
            cfg.kernel_enable_attestation = true;
            cfg.kernel_enable_update = true;
        }
        else
        {
            cfg.kernel_telemetry_tier = "core";
            cfg.kernel_enable_integrity = false;
            cfg.kernel_enable_attestation = false;
            cfg.kernel_enable_update = false;
        }

        cfg.kernel_sample_exec_pct = std::min<std::uint32_t>(100, cfg.kernel_sample_exec_pct);
        cfg.kernel_sample_integrity_pct = std::min<std::uint32_t>(100, cfg.kernel_sample_integrity_pct);
        cfg.kernel_sample_attestation_pct = std::min<std::uint32_t>(100, cfg.kernel_sample_attestation_pct);
        cfg.kernel_sample_update_pct = std::min<std::uint32_t>(100, cfg.kernel_sample_update_pct);
        cfg.kernel_sample_runtime_pct = std::min<std::uint32_t>(100, cfg.kernel_sample_runtime_pct);

        const std::string derived_base = detail::derive_http_base_from_agent_endpoint(cfg.endpoint);
        if (detail::trim_copy(cfg.telemetry_fallback_url).empty())
        {
            cfg.telemetry_fallback_url = derived_base;
        }
        if (detail::trim_copy(cfg.artifact_api_base_url).empty())
        {
            cfg.artifact_api_base_url = derived_base;
        }

        return cfg;
    }
};
