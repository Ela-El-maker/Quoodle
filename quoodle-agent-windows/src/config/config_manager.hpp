#pragma once

#include <cstdlib>
#include <string>
#include "config.hpp"

struct ConfigManager
{
    static AgentConfig load_from_env()
    {
        AgentConfig cfg;

        // Core settings
        if (const char *val = std::getenv("AGENT_ENDPOINT"))
            cfg.endpoint = val;
        if (const char *val = std::getenv("AGENT_DEVICE_ID"))
            cfg.device_id = val;
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
        if (const char *val = std::getenv("AGENT_CONNECTION_TIMEOUT_MS"))
            cfg.connection_timeout_ms = static_cast<std::uint32_t>(std::stoul(val));

        return cfg;
    }
};
