#pragma once

#include <string>

struct AgentConfig {
    std::string endpoint{"ws://localhost:8001/agent"};
    std::string device_id{"PC001"};
    std::string jwt;
};
