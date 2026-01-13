#include "dispatcher.hpp"

#include <chrono>
#include <random>
#include <sstream>

// ============== All Opcode Includes ==============
// SystemControl
#include "opcodes/lock_screen.hpp"
#include "opcodes/reboot.hpp"
#include "opcodes/shutdown.hpp"
#include "opcodes/logout.hpp"

// AgentInternal
#include "opcodes/ping.hpp"
#include "opcodes/collect_system_info.hpp"
#include "opcodes/process_list.hpp"
#include "opcodes/validate_update_package.hpp"

// UpdateAndStaging
#include "opcodes/stage_update.hpp"
#include "opcodes/commit_update.hpp"
#include "opcodes/rollback_update.hpp"

// SecurityIntegrity
#include "opcodes/attestation.hpp"
#include "opcodes/tamper_check.hpp"
#include "opcodes/self_repair.hpp"

// Utilities
#include "utils/logger.hpp"
#include "utils/json_canonicalizer.hpp"
#include "crypto/ed25519_wrapper.hpp"

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

    // Build a deterministic canonical payload for signing/verifying
    std::vector<std::pair<std::string, std::string>> fields = {
        {"error_code", std::to_string(error_code)},
        {"request_id", "\"" + utils::escape_json(request_id) + "\""},
        {"kernel_exec_id", "\"" + utils::escape_json(resp.kernel_exec_id) + "\""},
        {"result", "\"" + utils::escape_json(result) + "\""},
        {"status", "\"" + utils::escape_json(status) + "\""},
        {"timestamp", "\"" + utils::escape_json(resp.timestamp) + "\""},
        {"error_message", error_message.empty() ? "null" : "\"" + utils::escape_json(error_message) + "\""}};

    std::string payload = utils::canonical_object(fields);

#ifdef HAVE_SODIUM
    resp.sig = ed25519_sign_message(payload);
    if (resp.sig.empty())
    {
      resp.sig = std::to_string(std::hash<std::string>{}(payload));
    }
#else
    resp.sig = std::to_string(std::hash<std::string>{}(payload));
#endif

    return resp;
  }

} // namespace

// =====================================================================
// SystemControl Handlers
// =====================================================================

KernelResponse Dispatcher::handle_lock_screen(const std::string &request_id)
{
  utils::log_info("Dispatcher: Processing EXEC_LOCK_SCREEN for " + request_id);

  bool ok = execute_lock_screen();

  if (ok)
  {
    return wrap_response(request_id, "ok", "workstation_locked");
  }
  else
  {
    return wrap_response(request_id, "failed", "lock_failed", 5001, "WINAPI_LOCK_FAILED");
  }
}

KernelResponse Dispatcher::handle_reboot(const std::string &request_id, int delay_seconds)
{
  utils::log_info("Dispatcher: Processing EXEC_REBOOT for " + request_id + " (delay=" + std::to_string(delay_seconds) + "s)");

  bool ok = execute_reboot(delay_seconds);

  if (ok)
  {
    return wrap_response(request_id, "ok", "reboot_scheduled");
  }
  else
  {
    return wrap_response(request_id, "failed", "reboot_failed", 5002, "WINAPI_REBOOT_FAILED");
  }
}

KernelResponse Dispatcher::handle_shutdown(const std::string &request_id, bool force)
{
  utils::log_info("Dispatcher: Processing EXEC_SHUTDOWN for " + request_id + " (force=" + (force ? "true" : "false") + ")");

  bool ok = execute_shutdown(force);

  if (ok)
  {
    return wrap_response(request_id, "ok", "shutdown_initiated");
  }
  else
  {
    return wrap_response(request_id, "failed", "shutdown_failed", 5003, "WINAPI_SHUTDOWN_FAILED");
  }
}

KernelResponse Dispatcher::handle_logout(const std::string &request_id)
{
  utils::log_info("Dispatcher: Processing EXEC_LOGOUT for " + request_id);

  bool ok = execute_logout();

  if (ok)
  {
    return wrap_response(request_id, "ok", "user_logged_out");
  }
  else
  {
    return wrap_response(request_id, "failed", "logout_failed", 5004, "WINAPI_LOGOUT_FAILED");
  }
}

// =====================================================================
// AgentInternal Handlers
// =====================================================================

KernelResponse Dispatcher::handle_ping(const std::string &request_id)
{
  utils::log_info("Dispatcher: Processing EXEC_PING_KERNEL for " + request_id);

  std::string pong = execute_ping();

  return wrap_response(request_id, "ok", pong);
}

KernelResponse Dispatcher::handle_collect_system_info(const std::string &request_id, const std::vector<std::string> &fields)
{
  utils::log_info("Dispatcher: Processing EXEC_COLLECT_SYSTEM_INFO for " + request_id);

  auto info = execute_collect_system_info(fields);

  // Serialize the map to a JSON-like string for the result field
  std::ostringstream oss;
  oss << "{";
  bool first = true;
  for (const auto &kv : info)
  {
    if (!first)
      oss << ",";
    oss << "\"" << utils::escape_json(kv.first) << "\":\"" << utils::escape_json(kv.second) << "\"";
    first = false;
  }
  oss << "}";

  return wrap_response(request_id, "ok", oss.str());
}

KernelResponse Dispatcher::handle_get_process_list(const std::string &request_id, bool include_cmdline)
{
  utils::log_info("Dispatcher: Processing EXEC_GET_PROCESS_LIST for " + request_id);

  auto processes = execute_process_list(include_cmdline);

  // Serialize the list to a JSON array string
  std::ostringstream oss;
  oss << "[";
  for (size_t i = 0; i < processes.size(); ++i)
  {
    if (i > 0)
      oss << ",";
    oss << "\"" << utils::escape_json(processes[i]) << "\"";
  }
  oss << "]";

  return wrap_response(request_id, "ok", oss.str());
}

KernelResponse Dispatcher::handle_validate_update_package(const std::string &request_id, const std::string &path)
{
  utils::log_info("Dispatcher: Processing EXEC_VALIDATE_UPDATE_PACKAGE for " + request_id + " (path=" + path + ")");

  bool valid = execute_validate_update_package(path);

  if (valid)
  {
    return wrap_response(request_id, "ok", "package_valid");
  }
  else
  {
    return wrap_response(request_id, "failed", "package_invalid", 5005, "UPDATE_PACKAGE_VALIDATION_FAILED");
  }
}

// =====================================================================
// UpdateAndStaging Handlers
// =====================================================================

KernelResponse Dispatcher::handle_stage_update(const std::string &request_id, const std::string &package_path, bool sandbox)
{
  utils::log_info("Dispatcher: Processing STAGE_UPDATE for " + request_id + " (path=" + package_path + ", sandbox=" + (sandbox ? "true" : "false") + ")");

  std::string sandbox_id = execute_stage_update(package_path, sandbox);

  if (!sandbox_id.empty())
  {
    return wrap_response(request_id, "ok", sandbox_id);
  }
  else
  {
    return wrap_response(request_id, "failed", "staging_failed", 5001, "UPDATE_STAGING_FAILED");
  }
}

KernelResponse Dispatcher::handle_commit_update(const std::string &request_id, const std::string &sandbox_id)
{
  utils::log_info("Dispatcher: Processing COMMIT_UPDATE for " + request_id + " (sandbox_id=" + sandbox_id + ")");

  bool ok = execute_commit_update(sandbox_id);

  if (ok)
  {
    return wrap_response(request_id, "ok", "update_committed");
  }
  else
  {
    return wrap_response(request_id, "failed", "commit_failed", 5006, "UPDATE_COMMIT_FAILED");
  }
}

KernelResponse Dispatcher::handle_rollback_update(const std::string &request_id, const std::string &snapshot_id)
{
  utils::log_info("Dispatcher: Processing ROLLBACK_UPDATE for " + request_id + " (snapshot_id=" + snapshot_id + ")");

  bool ok = execute_rollback_update(snapshot_id);

  if (ok)
  {
    return wrap_response(request_id, "ok", "rollback_completed");
  }
  else
  {
    return wrap_response(request_id, "failed", "rollback_failed", 5007, "UPDATE_ROLLBACK_FAILED");
  }
}

// =====================================================================
// SecurityIntegrity Handlers
// =====================================================================

KernelResponse Dispatcher::handle_run_attestation(const std::string &request_id, bool include_tpm)
{
  utils::log_info("Dispatcher: Processing EXEC_RUN_ATTESTATION for " + request_id + " (include_tpm=" + (include_tpm ? "true" : "false") + ")");

  auto attestation = execute_attestation();

  // Serialize the attestation map to a JSON-like string
  std::ostringstream oss;
  oss << "{";
  bool first = true;
  for (const auto &kv : attestation)
  {
    if (!first)
      oss << ",";
    oss << "\"" << utils::escape_json(kv.first) << "\":\"" << utils::escape_json(kv.second) << "\"";
    first = false;
  }
  oss << "}";

  return wrap_response(request_id, "ok", oss.str());
}

KernelResponse Dispatcher::handle_run_tamper_check(const std::string &request_id)
{
  utils::log_info("Dispatcher: Processing EXEC_RUN_TAMPER_CHECK for " + request_id);

  bool ok = execute_tamper_check();

  if (ok)
  {
    return wrap_response(request_id, "ok", "integrity_verified");
  }
  else
  {
    return wrap_response(request_id, "failed", "tamper_detected", 3001, "TAMPER_DETECTED");
  }
}

KernelResponse Dispatcher::handle_self_repair(const std::string &request_id)
{
  utils::log_info("Dispatcher: Processing EXEC_SELF_REPAIR for " + request_id);

  bool ok = execute_self_repair();

  if (ok)
  {
    return wrap_response(request_id, "ok", "repair_completed");
  }
  else
  {
    return wrap_response(request_id, "failed", "repair_failed", 5008, "SELF_REPAIR_FAILED");
  }
}

// =====================================================================
// Fallback Handler
// =====================================================================

KernelResponse Dispatcher::handle_unknown(const std::string &request_id, const std::string &opcode)
{
  utils::log_error("Dispatcher: Received unknown opcode: " + opcode);
  return wrap_response(request_id, "invalid_opcode", "unknown_opcode", 4002, "INVALID_OPCODE");
}
