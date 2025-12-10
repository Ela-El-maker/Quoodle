#include "../ws_protocol.hpp"
#include "../../kernel/ioctl_client.hpp"
#include <string>

std::string handle_command_delivery(const std::string& device_id, const std::string& session_id, const std::string& command_id, const std::string& trace_id, const std::string& method) {
    IoctlClient ioctl;
    if (method == "lock_screen") {
        (void)ioctl.lock_screen(command_id);
    } else if (method == "ping") {
        (void)ioctl.ping(command_id);
    }
    return build_command_result_json(device_id, session_id, command_id, trace_id, "completed", "ok", "done", "", "", 0, "");
}
