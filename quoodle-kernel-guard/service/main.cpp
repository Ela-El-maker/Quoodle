#include "dispatcher.hpp"
#include "utils/logger.hpp"
#include "crypto/ed25519_verify_wrapper.hpp"

#ifdef _WIN32
#include <windows.h>
#endif

#include <iostream>
#include <string>
#include <sstream>
#include <thread>
#include <vector>

// --- JSON Parsing Helpers ---

static std::string extract_json_string(const std::string &json, const std::string &key)
{
  std::string needle = '"' + key + '"';
  auto pos = json.find(needle);
  if (pos == std::string::npos)
    return {};
  auto colon = json.find(':', pos + needle.size());
  if (colon == std::string::npos)
    return {};
  auto first_quote = json.find('"', colon);
  if (first_quote == std::string::npos)
    return {};
  auto second_quote = json.find('"', first_quote + 1);
  if (second_quote == std::string::npos)
    return {};
  return json.substr(first_quote + 1, second_quote - first_quote - 1);
}

static int extract_json_int(const std::string &json, const std::string &key, int default_val = 0)
{
  std::string needle = '"' + key + '"';
  auto pos = json.find(needle);
  if (pos == std::string::npos)
    return default_val;
  auto colon = json.find(':', pos + needle.size());
  if (colon == std::string::npos)
    return default_val;
  // Skip whitespace
  size_t start = colon + 1;
  while (start < json.size() && (json[start] == ' ' || json[start] == '\t'))
    start++;
  if (start >= json.size())
    return default_val;
  // Parse integer
  std::string num_str;
  while (start < json.size() && (isdigit(json[start]) || json[start] == '-'))
  {
    num_str += json[start];
    start++;
  }
  if (num_str.empty())
    return default_val;
  return std::stoi(num_str);
}

static bool extract_json_bool(const std::string &json, const std::string &key, bool default_val = false)
{
  std::string needle = '"' + key + '"';
  auto pos = json.find(needle);
  if (pos == std::string::npos)
    return default_val;
  auto colon = json.find(':', pos + needle.size());
  if (colon == std::string::npos)
    return default_val;
  // Skip whitespace
  size_t start = colon + 1;
  while (start < json.size() && (json[start] == ' ' || json[start] == '\t'))
    start++;
  if (start >= json.size())
    return default_val;
  // Check for true/false
  if (json.substr(start, 4) == "true")
    return true;
  if (json.substr(start, 5) == "false")
    return false;
  return default_val;
}

static std::vector<std::string> extract_json_string_array(const std::string &json, const std::string &key)
{
  std::vector<std::string> result;
  std::string needle = '"' + key + '"';
  auto pos = json.find(needle);
  if (pos == std::string::npos)
    return result;
  auto colon = json.find(':', pos + needle.size());
  if (colon == std::string::npos)
    return result;
  auto bracket = json.find('[', colon);
  if (bracket == std::string::npos)
    return result;
  auto close_bracket = json.find(']', bracket);
  if (close_bracket == std::string::npos)
    return result;
  // Extract strings within the array
  size_t i = bracket + 1;
  while (i < close_bracket)
  {
    auto quote1 = json.find('"', i);
    if (quote1 == std::string::npos || quote1 >= close_bracket)
      break;
    auto quote2 = json.find('"', quote1 + 1);
    if (quote2 == std::string::npos || quote2 >= close_bracket)
      break;
    result.push_back(json.substr(quote1 + 1, quote2 - quote1 - 1));
    i = quote2 + 1;
  }
  return result;
}

static std::string json_escape(const std::string &s)
{
  std::string out;
  for (char c : s)
  {
    switch (c)
    {
    case '\\':
      out += "\\\\";
      break;
    case '"':
      out += "\\\"";
      break;
    case '\n':
      out += "\\n";
      break;
    case '\r':
      out += "\\r";
      break;
    case '\t':
      out += "\\t";
      break;
    default:
      out += c;
      break;
    }
  }
  return out;
}

static std::string to_json(const KernelResponse &r)
{
  std::ostringstream oss;
  oss << "{"
      << "\"request_id\":\"" << json_escape(r.request_id) << "\","
      << "\"status\":\"" << json_escape(r.status) << "\","
      << "\"kernel_exec_id\":\"" << json_escape(r.kernel_exec_id) << "\","
      << "\"timestamp\":\"" << json_escape(r.timestamp) << "\","
      << "\"result\":\"" << json_escape(r.result) << "\","
      << "\"error_code\":" << r.error_code << ","
      << "\"error_message\":\"" << json_escape(r.error_message) << "\","
      << "\"sig\":\"" << json_escape(r.sig) << "\""
      << "}";
  return oss.str();
}

/**
 * dispatch_opcode - Routes an opcode to the appropriate handler.
 * Supports all 14 opcodes from the spec:
 *
 * SystemControl:
 *   - EXEC_LOCK_SCREEN, lock_screen
 *   - EXEC_REBOOT, reboot
 *   - EXEC_SHUTDOWN, shutdown
 *   - EXEC_LOGOUT, logout
 *
 * AgentInternal:
 *   - EXEC_PING_KERNEL, ping
 *   - EXEC_COLLECT_SYSTEM_INFO, collect_system_info
 *   - EXEC_GET_PROCESS_LIST, get_process_list
 *   - EXEC_VALIDATE_UPDATE_PACKAGE, validate_update_package
 *
 * UpdateAndStaging:
 *   - STAGE_UPDATE, stage_update
 *   - COMMIT_UPDATE, commit_update
 *   - ROLLBACK_UPDATE, rollback_update
 *
 * SecurityIntegrity:
 *   - EXEC_RUN_ATTESTATION, run_attestation
 *   - EXEC_RUN_TAMPER_CHECK, run_tamper_check
 *   - EXEC_SELF_REPAIR, self_repair
 */
static KernelResponse dispatch_opcode(Dispatcher &disp, const std::string &req, const std::string &opcode, const std::string &request_id)
{
  // ============== SystemControl ==============
  if (opcode == "EXEC_LOCK_SCREEN" || opcode == "lock_screen")
  {
    return disp.handle_lock_screen(request_id);
  }
  else if (opcode == "EXEC_REBOOT" || opcode == "reboot")
  {
    int delay = extract_json_int(req, "delay_seconds", 0);
    return disp.handle_reboot(request_id, delay);
  }
  else if (opcode == "EXEC_SHUTDOWN" || opcode == "shutdown")
  {
    bool force = extract_json_bool(req, "force", false);
    return disp.handle_shutdown(request_id, force);
  }
  else if (opcode == "EXEC_LOGOUT" || opcode == "logout")
  {
    return disp.handle_logout(request_id);
  }
  // ============== AgentInternal ==============
  else if (opcode == "EXEC_PING_KERNEL" || opcode == "ping")
  {
    return disp.handle_ping(request_id);
  }
  else if (opcode == "EXEC_COLLECT_SYSTEM_INFO" || opcode == "collect_system_info")
  {
    auto fields = extract_json_string_array(req, "fields");
    return disp.handle_collect_system_info(request_id, fields);
  }
  else if (opcode == "EXEC_GET_PROCESS_LIST" || opcode == "get_process_list")
  {
    bool include_cmdline = extract_json_bool(req, "include_cmdline", false);
    return disp.handle_get_process_list(request_id, include_cmdline);
  }
  else if (opcode == "EXEC_VALIDATE_UPDATE_PACKAGE" || opcode == "validate_update_package")
  {
    std::string path = extract_json_string(req, "path");
    return disp.handle_validate_update_package(request_id, path);
  }
  // ============== UpdateAndStaging ==============
  else if (opcode == "STAGE_UPDATE" || opcode == "stage_update")
  {
    std::string package_path = extract_json_string(req, "package_path");
    bool sandbox = extract_json_bool(req, "sandbox", true);
    return disp.handle_stage_update(request_id, package_path, sandbox);
  }
  else if (opcode == "COMMIT_UPDATE" || opcode == "commit_update")
  {
    std::string sandbox_id = extract_json_string(req, "sandbox_id");
    return disp.handle_commit_update(request_id, sandbox_id);
  }
  else if (opcode == "ROLLBACK_UPDATE" || opcode == "rollback_update")
  {
    std::string snapshot_id = extract_json_string(req, "snapshot_id");
    return disp.handle_rollback_update(request_id, snapshot_id);
  }
  // ============== SecurityIntegrity ==============
  else if (opcode == "EXEC_RUN_ATTESTATION" || opcode == "run_attestation")
  {
    bool include_tpm = extract_json_bool(req, "include_tpm", false);
    return disp.handle_run_attestation(request_id, include_tpm);
  }
  else if (opcode == "EXEC_RUN_TAMPER_CHECK" || opcode == "run_tamper_check")
  {
    return disp.handle_run_tamper_check(request_id);
  }
  else if (opcode == "EXEC_SELF_REPAIR" || opcode == "self_repair")
  {
    return disp.handle_self_repair(request_id);
  }
  // ============== Unknown ==============
  else
  {
    return disp.handle_unknown(request_id, opcode);
  }
}

// --- Main Entry Point ---

int main(int argc, char **argv)
{
  // CLI one-shot mode: kernel_service --once <opcode> <request_id> [json_params]
  if (argc >= 2 && std::string(argv[1]) == "--once")
  {
    const char *allow_fallback = std::getenv("ALLOW_EXEC_FALLBACK");
    if (!(allow_fallback && std::string(allow_fallback) == "1"))
    {
      utils::log_error("--once mode disabled: ALLOW_EXEC_FALLBACK!=1");
      return 1;
    }

    std::string opcode = (argc >= 3) ? argv[2] : std::string();
    std::string request_id = (argc >= 4) ? argv[3] : std::string("req-cli");
    std::string json_params = (argc >= 5) ? argv[4] : std::string("{}");

    Dispatcher disp;
    KernelResponse resp = dispatch_opcode(disp, json_params, opcode, request_id);
    std::cout << to_json(resp) << std::endl;
    return 0;
  }

  utils::log_info("KernelService starting (named-pipe server mode)");
#ifdef _WIN32
  auto pipe_server = [&]()
  {
    Dispatcher disp;
    const char *pipeName = "\\\\.\\pipe\\KernelService";

    while (true)
    {
      // Note: Use &sa if you implemented the Security Descriptor from the previous step
      HANDLE hPipe = CreateNamedPipeA(
          pipeName,
          PIPE_ACCESS_DUPLEX,
          PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
          PIPE_UNLIMITED_INSTANCES,
          8192,
          8192,
          0,
          NULL);

      if (hPipe == INVALID_HANDLE_VALUE)
      {
        utils::log_error("pipe_server: CreateNamedPipeA failed");
        std::this_thread::sleep_for(std::chrono::seconds(1));
        continue;
      }

      if (ConnectNamedPipe(hPipe, NULL) || GetLastError() == ERROR_PIPE_CONNECTED)
      {
        char buffer[8192];
        DWORD read = 0;
        if (ReadFile(hPipe, buffer, sizeof(buffer), &read, NULL) && read > 0)
        {
          std::string req(buffer, read);
          std::string opcode = extract_json_string(req, "opcode");
          std::string request_id = extract_json_string(req, "request_id");
          if (request_id.empty())
            request_id = "req-unknown";

          // Optional signed requests: if a signature and signed_payload are included,
          // verify using configured controller public key (KERNEL_CONTROLLER_PUBKEY_B64).
          std::string sig = extract_json_string(req, "sig");
          std::string signed_payload = extract_json_string(req, "signed_payload");
          if (!sig.empty() && !signed_payload.empty())
          {
            // ed25519_verify_message will attempt to load the controller public key
            // from the provided string or from environment/file (KERNEL_CONTROLLER_PUBKEY_B64 or KERNEL_CONTROLLER_PUBKEY_PATH).
            if (!ed25519_verify_message(signed_payload, sig, std::string()))
            {
              utils::log_error("pipe_server: signature verification failed or pubkey missing");
              KernelResponse resp_err = disp.handle_unknown(request_id, "signature_invalid");
              std::string out_err = to_json(resp_err);
              DWORD written_err = 0;
              WriteFile(hPipe, out_err.c_str(), static_cast<DWORD>(out_err.size()), &written_err, NULL);
              FlushFileBuffers(hPipe);
              DisconnectNamedPipe(hPipe);
              CloseHandle(hPipe);
              continue;
            }
          }

          // Route to appropriate handler using dispatch_opcode (supports all 14 opcodes)
          KernelResponse resp = dispatch_opcode(disp, req, opcode, request_id);

          std::string out = to_json(resp);
          DWORD written = 0;
          WriteFile(hPipe, out.c_str(), (DWORD)out.size(), &written, NULL);
          FlushFileBuffers(hPipe);
        }
      }
      DisconnectNamedPipe(hPipe);
      CloseHandle(hPipe);
    }
  };
  pipe_server();
#endif
  return 0;
}
