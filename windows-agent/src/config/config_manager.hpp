#pragma once

#include "config.hpp"

struct ConfigManager
{
    static AgentConfig load_from_env()
    {
        AgentConfig cfg;
        if (const char *val = std::getenv("AGENT_ENDPOINT"))
            cfg.endpoint = val;
        if (const char *val = std::getenv("AGENT_DEVICE_ID"))
            cfg.device_id = val;
        if (const char *val = std::getenv("AGENT_JWT"))
            cfg.jwt = val;
        return cfg;
    }
};
