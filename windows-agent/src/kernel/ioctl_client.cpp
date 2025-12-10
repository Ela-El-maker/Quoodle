#include "ioctl_client.hpp"

#include <random>
#include <sstream>
#include <string>

namespace {

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

std::string random_exec_id() {
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<uint32_t> dis;
    std::ostringstream oss;
    oss << "kexec-" << std::hex << dis(gen);
    return oss.str();
}

KernelExecResult wrap_result(const std::string& request_id, const std::string& status, const std::string& result, int error_code = 0, const std::string& error_message = "") {
    KernelExecResult r;
    r.request_id = request_id;
    r.status = status;
    r.kernel_exec_id = random_exec_id();
    r.timestamp = iso_timestamp();
    r.result = result;
    r.error_code = error_code;
    r.error_message = error_message;
    r.sig = std::to_string(std::hash<std::string>{}(request_id + status + result + std::to_string(error_code) + error_message));
    return r;
}

}  // namespace

KernelExecResult IoctlClient::lock_screen(const std::string& request_id) {
    // TODO: real IOCTL to kernel-service driver
    return wrap_result(request_id, "ok", "lock_screen_executed");
}

KernelExecResult IoctlClient::ping(const std::string& request_id) {
    return wrap_result(request_id, "ok", "pong");
}
