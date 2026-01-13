#include "../ws_protocol.hpp"
#include <string>

std::string handle_auth_ack(const std::string& device_id, const std::string& session_id) {
    (void)device_id;
    return build_signed_heartbeat_json(device_id, session_id, "alive", 0, "ok");
}
