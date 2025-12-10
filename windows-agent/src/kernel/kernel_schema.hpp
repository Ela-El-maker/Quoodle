#pragma once

#include <string>

struct KernelRequest {
    std::string request_id;
    std::string opcode;
    std::string params;
    int agent_sequence{0};
    std::string policy_hash;
    std::string command_message_id;
};

struct KernelResponseSchema {
    std::string request_id;
    std::string status;
    std::string kernel_exec_id;
    std::string timestamp;
    int error_code{0};
    std::string error_message;
    std::string result;
    std::string signature;
};
