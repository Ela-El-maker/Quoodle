#include <cstdlib>
#include <iostream>
#include <string>

#include "ws/ws_client.hpp"
#include "ws/ws_protocol.hpp"
#include "config/config_manager.hpp"
#include "comm/communicator.hpp"
#include "command/dispatcher.hpp"

int main()
{
    AgentConfig cfg = ConfigManager::load_from_env();

    if (cfg.jwt.empty())
    {
        std::cerr << "Missing AGENT_JWT environment variable; cannot build AUTH message." << std::endl;
        return 1;
    }

    auto envelope = build_auth_envelope(cfg.device_id, cfg.jwt);
    std::string auth_json = build_signed_auth_json(envelope);

    Communicator comm(cfg.endpoint, cfg.device_id);
    comm.set_initial_message(auth_json);

    // CommandDispatcher is instantiated here so other modules can use it when integrating.
    CommandDispatcher dispatcher;

    // Blocking run; WsClient currently implements its own loop.
    comm.start();

    return 0;
}
