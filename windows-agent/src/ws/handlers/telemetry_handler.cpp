#include "../ws_protocol.hpp"
#include <string>

std::string build_telemetry_sample(const std::string& device_id, const std::string& session_id) {
    return build_signed_telemetry_json(device_id, session_id);
}
