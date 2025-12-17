#pragma once

#include <string>
#include "../ws/ws_client.hpp"

class Communicator
{
public:
    Communicator(const std::string &endpoint, const std::string &device_id)
        : client_(endpoint, device_id) {}

    void set_initial_message(const std::string &msg) { client_.set_initial_message(msg); }

    // Blocking run — for now delegates to WsClient's connect_and_run
    void start() { client_.connect_and_run(); }

private:
    WsClient client_;
};
