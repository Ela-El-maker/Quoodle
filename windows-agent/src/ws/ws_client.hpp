#pragma once

#include <string>

class WsClient {
public:
    explicit WsClient(std::string endpoint);

    void set_initial_message(const std::string& message);

    void connect_and_run();

private:
    std::string endpoint_;
    std::string initial_message_;
};
