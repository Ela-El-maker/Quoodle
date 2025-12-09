#pragma once

#include <string>

struct KernelExecResult {
    std::string request_id;
    std::string status;
    std::string kernel_exec_id;
    std::string timestamp;
    std::string result;
    std::string sig;
};

class IoctlClient {
public:
    KernelExecResult lock_screen(const std::string& request_id);
    KernelExecResult ping(const std::string& request_id);
};
