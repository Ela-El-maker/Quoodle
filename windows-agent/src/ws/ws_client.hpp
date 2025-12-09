#pragma once

#include <string>

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
};
