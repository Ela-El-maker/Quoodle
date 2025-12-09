#include <cstdlib>
#include <iostream>
#include <string>

#include "ws/ws_client.hpp"
#include "ws/ws_protocol.hpp"

struct AgentConfig {
    std::string endpoint{"ws://localhost:8001/agent"};
    std::string device_id{"PC001"};
    std::string jwt;

    static AgentConfig from_env() {
        AgentConfig cfg;
        if (const char* val = std::getenv("AGENT_ENDPOINT")) cfg.endpoint = val;
        if (const char* val = std::getenv("AGENT_DEVICE_ID")) cfg.device_id = val;
        if (const char* val = std::getenv("AGENT_JWT")) cfg.jwt = val;
        return cfg;
    }
};

int main() {
    AgentConfig cfg = AgentConfig::from_env();

    if (cfg.jwt.empty()) {
        std::cerr << "Missing AGENT_JWT environment variable; cannot build AUTH message." << std::endl;
        return 1;
    }

    auto envelope = build_auth_envelope(cfg.device_id, cfg.jwt);
    std::string auth_json = build_signed_auth_json(envelope);

    WsClient client(cfg.endpoint);
    client.set_initial_message(auth_json);
    client.connect_and_run();

    return 0;
}
