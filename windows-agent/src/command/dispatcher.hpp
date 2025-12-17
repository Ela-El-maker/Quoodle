#pragma once

#include <string>
#include "../kernel/ioctl_client.hpp"

class CommandDispatcher
{
public:
    CommandDispatcher() = default;

    // Simple dispatch that maps known method names to kernel operations.
    KernelExecResult dispatch(const std::string &method, const std::string &request_id)
    {
        if (method == "lock_screen")
        {
            return ioctl_.lock_screen(request_id);
        }
        if (method == "ping")
        {
            return ioctl_.ping(request_id);
        }
        // unknown -> return an error-like result
        KernelExecResult r;
        r.request_id = request_id;
        r.status = "invalid_opcode";
        r.result = "";
        r.error_code = 4002;
        r.error_message = "INVALID_OPCODE";
        return r;
    }

private:
    IoctlClient ioctl_;
};
