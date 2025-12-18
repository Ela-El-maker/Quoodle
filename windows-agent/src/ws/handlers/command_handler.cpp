#include "../ws_protocol.hpp"
#include "../../kernel/ioctl_client.hpp"
#include <string>

static IoctlClient g_ioctl;
std::string handle_command_delivery(const std::string& device_id, 
                                    const std::string& session_id, 
                                    const std::string& command_id, 
                                    const std::string& trace_id, 
                                    const std::string& method) {
  auto res = g_ioctl.lock_screen(command_id);
    
    // Now you have a rich KernelExecResult to return to the server!
    return build_command_result_json(
        device_id, 
        session_id, 
        command_id, 
        trace_id, 
        res.status,     // "completed", "failed", etc
        res.result,     // "ok", "error"
        res.error_message, 
        "", "", 
        res.error_code, 
        res.error_message
    );
}
