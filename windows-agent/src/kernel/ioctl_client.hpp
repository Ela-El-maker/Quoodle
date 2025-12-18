#pragma once

#include <string>
#ifdef _WIN32
#include <windows.h>
#endif

/**
 * KernelExecResult
 * Represents the structured response from the privileged kernel service.
 * Aligned with the project's JSON communication spec.
 */
struct KernelExecResult
{
    std::string request_id;
    std::string status;
    std::string kernel_exec_id;
    std::string timestamp;
    std::string result;
    int error_code{0};
    std::string error_message;
    std::string sig;
};

/**
 * IoctlClient
 * The gateway for the User-Mode Agent to request privileged operations.
 * It abstracts the IPC (Inter-Process Communication) layer.
 */
class IoctlClient
{
public:
    IoctlClient() = default;
    ~IoctlClient();

    // Public API for supported Kernel operations
    KernelExecResult lock_screen(const std::string &request_id);
    KernelExecResult ping(const std::string &request_id);

private:
    bool ensure_connection(); // Helper to reconnect if pipe drops
    void disconnect();

    // Core communication handler (Pipe + Fallback)
    std::string execute_request(const std::string &opcode, const std::string &request_id);

    // Internal JSON parsing
    KernelExecResult parse_result_from_json(const std::string &json);

#ifdef _WIN32
    HANDLE hPipe = INVALID_HANDLE_VALUE;
#endif
};
