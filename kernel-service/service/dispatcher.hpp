#pragma once

#include <string>

struct KernelResponse {
    std::string request_id;
    std::string status;
    std::string kernel_exec_id;
    std::string timestamp;
    std::string result;
    int error_code{0};
    std::string error_message;
    std::string sig;
};

class Dispatcher {
public:
    KernelResponse handle_lock_screen(const std::string& request_id);
    KernelResponse handle_ping(const std::string& request_id);
    KernelResponse handle_unknown(const std::string& request_id, const std::string& opcode);
};
