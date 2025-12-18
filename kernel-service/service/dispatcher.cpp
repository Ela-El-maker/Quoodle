#include "dispatcher.hpp"

#include <chrono>
#include <random>
#include <sstream>

#include "opcodes/lock_screen.hpp"
#include "opcodes/ping.hpp"
#include "utils/logger.hpp"

namespace
{
  // Generates a unique ID for every command execution
  std::string generate_exec_id()
  {
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<uint32_t> dis(0, 0xFFFFFFFF);
    std::ostringstream oss;
    oss << "kexec-" << std::hex << dis(gen);
    return oss.str();
  }
  // Returns a standard ISO 8601 timestamp
  std::string iso_timestamp()
  {
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
    std::strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &tm);
    return std::string(buffer);
  }
  // Helper to package the response consistently
  KernelResponse wrap_response(const std::string &request_id, const std::string &status, const std::string &result, int error_code = 0, const std::string &error_message = "")
  {
    KernelResponse resp;
    resp.request_id = request_id;
    resp.status = status;
    resp.kernel_exec_id = generate_exec_id();
    resp.timestamp = iso_timestamp();
    resp.result = result;
    resp.error_code = error_code;
    resp.error_message = error_message;
    // Sign response: prefer Ed25519 when available; otherwise fall back to hash-based signature
    std::string payload = request_id + status + result + std::to_string(error_code);
    std::string sig;
#ifdef HAVE_SODIUM
    sig = ed25519_sign_message(payload);
    if (sig.empty())
    {
      // fallback to hash if signing failed
      sig = std::to_string(std::hash<std::string>{}(payload));
    }
#else
    sig = std::to_string(std::hash<std::string>{}(payload));
#endif
    resp.sig = sig;
    return resp;
  }

} // namespace

KernelResponse Dispatcher::handle_lock_screen(const std::string &request_id)
{
  utils::log_info("Dispatcher: Processing lock_screen for " + request_id);

  // Call the actual Windows API wrapper
  bool ok = execute_lock_screen();

  if (ok)
  {
    return wrap_response(request_id, "success", "workstation_locked");
  }
  else
  {
    return wrap_response(request_id, "error", "failed", 5001, "WINAPI_LOCK_FAILED");
  }
}

KernelResponse Dispatcher::handle_ping(const std::string &request_id)
{
  utils::log_info("Dispatcher: Processing ping for " + request_id);

  // Call the ping implementation
  std::string pong = execute_ping();

  return wrap_response(request_id, "success", pong);
}

KernelResponse Dispatcher::handle_unknown(const std::string &request_id, const std::string &opcode)
{
  utils::log_error("Dispatcher: Received unknown opcode: " + opcode);
  return wrap_response(request_id, "error", "unknown_opcode", 4004, "OPCODE_NOT_SUPPORTED");
}
