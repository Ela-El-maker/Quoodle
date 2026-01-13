#include <string>

std::string handle_error(const std::string& related_message_id, const std::string& error_message) {
    return std::string("error:") + related_message_id + ":" + error_message;
}
