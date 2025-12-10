#include "dispatcher.hpp"

#include <chrono>
#include <random>
#include <sstream>

#include "opcodes/lock_screen.hpp"
#include "opcodes/ping.hpp"
#include "utils/logger.hpp"

namespace {

std::string generate_exec_id() {
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<uint32_t> dis(0, 0xFFFFFFFF);
    std::ostringstream oss;
    oss << "kexec-" << std::hex << dis(gen);
    return oss.str();
}

std::string iso_timestamp() {
    using namespace std::chrono;
    auto now = system_clock::now();
    std::time_t t = system_clock::to_time_t(now);
    std::tm tm{};
#ifdef _WIN32
    gmtime_s(&tm, &t);
#else
    gmtime_r(&t, &tm);
#endif
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%04d-%02d-%02dT%02d:%02d:%02dZ",
                  tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
                  tm.tm_hour, tm.tm_min, tm.tm_sec);
    return std::string(buffer);
}

KernelResponse wrap_response(const std::string& request_id, const std::string& status, const std::string& result, int error_code = 0, const std::string& error_message = "") {
    KernelResponse resp;
    resp.request_id = request_id;
    resp.status = status;
    resp.kernel_exec_id = generate_exec_id();
    resp.timestamp = iso_timestamp();
    resp.result = result;
    resp.error_code = error_code;
    resp.error_message = error_message;
    resp.sig = std::to_string(std::hash<std::string>{}(request_id + status + result + std::to_string(error_code) + error_message));
    return resp;
}

}  // namespace

KernelResponse Dispatcher::handle_lock_screen(const std::string& request_id) {
    utils::log_info("lock_screen invoked");
    // Minimal placeholder: return success without real IOCTL
    return wrap_response(request_id, "ok", "lock_screen_executed");
}

KernelResponse Dispatcher::handle_ping(const std::string& request_id) {
    utils::log_info("ping invoked");
    return wrap_response(request_id, "ok", "pong");
}

KernelResponse Dispatcher::handle_unknown(const std::string& request_id, const std::string& opcode) {
    utils::log_error("invalid opcode: " + opcode);
    return wrap_response(request_id, "invalid_opcode", "{}", 4002, "INVALID_OPCODE");
}
