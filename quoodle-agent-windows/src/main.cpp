#include <atomic>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <string>

#include "ws/ws_client.hpp"
#include "ws/ws_protocol.hpp"
#include "config/config_manager.hpp"
#include "comm/communicator.hpp"
#include "command/dispatcher.hpp"
#include "logging/logger.hpp"

// Global communicator pointer for signal handler
static std::atomic<Communicator *> g_communicator{nullptr};

static void signal_handler(int signal)
{
    if (auto *comm = g_communicator.load(std::memory_order_acquire))
    {
        Logger::log(LogLevel::Info, "received signal " + std::to_string(signal) + ", shutting down...");
        comm->shutdown();
    }
}

int main()
{
    Logger::log(LogLevel::Info, "Quoodle Agent starting...");

    AgentConfig cfg = ConfigManager::load_from_env();

    if (cfg.jwt.empty())
    {
        Logger::log(LogLevel::Error, "Missing AGENT_JWT environment variable; cannot build AUTH message.");
        return 1;
    }

    auto envelope = build_auth_envelope(cfg.device_id, cfg.jwt);
    std::string auth_json = build_signed_auth_json(envelope);

    // Create communicator with full config (enables reconnection settings)
    Communicator comm(cfg);
    comm.set_initial_message(auth_json);

    // Set up signal handlers for graceful shutdown
    g_communicator.store(&comm, std::memory_order_release);
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    // Optional: Log connection state changes
    comm.on_state_change([](ConnectionState state, const std::string &reason)
                         {
        std::string state_str;
        switch (state) {
            case ConnectionState::Connected:
                state_str = "CONNECTED";
                break;
            case ConnectionState::Reconnecting:
                state_str = "RECONNECTING";
                break;
            case ConnectionState::Failed:
                state_str = "FAILED";
                break;
            default:
                return; // Don't log other states
        }
        Logger::log(LogLevel::Info, "Connection: " + state_str + 
                    (reason.empty() ? "" : " - " + reason)); });

    // CommandDispatcher is instantiated here so other modules can use it when integrating.
    CommandDispatcher dispatcher;

    Logger::log(LogLevel::Info, "Starting WebSocket client with reconnection support");
    Logger::log(LogLevel::Info, "Endpoint: " + cfg.endpoint);
    Logger::log(LogLevel::Info, "Device ID: " + cfg.device_id);

    // Blocking run with automatic reconnection
    comm.start();

    // Cleanup
    g_communicator.store(nullptr, std::memory_order_release);
    Logger::log(LogLevel::Info, "Quoodle Agent stopped");

    return 0;
}
