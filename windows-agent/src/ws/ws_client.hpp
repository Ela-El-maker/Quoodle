#pragma once

#include <string>

#include "../agent_state.hpp"
#include "../logging/logger.hpp"
#include "../ota/ota_manager.hpp"
#include "../quarantine/quarantine_manager.hpp"
#include "../recovery/recovery_manager.hpp"

class WsClient {
public:
    WsClient(std::string endpoint, std::string device_id);

    void set_initial_message(const std::string& message);

    void connect_and_run();

private:
    std::string endpoint_;
    std::string device_id_;
    std::string initial_message_;
    bool heartbeat_sent_{false};
    bool telemetry_sent_{false};
    std::string last_session_id_;
    AgentState state_;
    OTAManager ota_;
    QuarantineManager quarantine_;
    RecoveryManager recovery_;
};
