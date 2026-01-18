#include "dispatcher.hpp"
#include "utils/logger.hpp"
#include "utils/json_canonicalizer.hpp"
#include "crypto/ed25519_verify_wrapper.hpp"

#ifdef _WIN32
#include <windows.h>
#endif

#include <iostream>
#include <string>
#include <sstream>
#include <thread>
#include <vector>
#include <algorithm>

// --- Configuration ---

/**
 * Check if signature verification is required.
 * Set KERNEL_REQUIRE_SIGNATURE=1 to enforce signature verification on all requests.
 * In production, this should always be enabled.
 */
static bool is_signature_required()
{
  const char *env = std::getenv("KERNEL_REQUIRE_SIGNATURE");
  if (!env) {
      // SECURE BY DEFAULT: If variable is missing, require signature.
      utils::log_info("KERNEL_REQUIRE_SIGNATURE not set. Defaulting to ENABLED (Secure).");
      return true;
  }
  return std::string(env) == "1";
}

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

// --- Request Signature Verification ---

/**
 * Build a canonical payload from the request for signature verification.
 * Per spec, the signed payload includes these fields in lexicographic order:
 *   - agent_sequence
 *   - command_message_id
 *   - opcode
 *   - params (as JSON string)
 *   - policy_hash
 *   - request_id
 *   - timestamp
 *
 * The signature field itself is NOT included in the canonical payload.
 */
static std::string build_canonical_request_payload(const std::string &req)
{
  // Extract all signable fields
  std::string request_id = extract_json_string(req, "request_id");
  std::string timestamp = extract_json_string(req, "timestamp");
  std::string opcode = extract_json_string(req, "opcode");
  std::string policy_hash = extract_json_string(req, "policy_hash");
  std::string command_message_id = extract_json_string(req, "command_message_id");
  int agent_sequence = extract_json_int(req, "agent_sequence", 0);

  // Extract params as raw JSON substring (between "params": and the next field)
  std::string params_json = "{}";
  auto params_pos = req.find("\"params\"");
  if (params_pos != std::string::npos)
  {
    auto colon = req.find(':', params_pos);
    if (colon != std::string::npos)
    {
      // Skip whitespace
      size_t start = colon + 1;
      while (start < req.size() && (req[start] == ' ' || req[start] == '\t' || req[start] == '\n'))
        start++;

      if (start < req.size() && req[start] == '{')
      {
        // Find matching closing brace
        int depth = 1;
        size_t end = start + 1;
        while (end < req.size() && depth > 0)
        {
          if (req[end] == '{')
            depth++;
          else if (req[end] == '}')
            depth--;
          end++;
        }
        params_json = req.substr(start, end - start);
      }
    }
  }

  // Build canonical object with fields in lexicographic order
  std::vector<std::pair<std::string, std::string>> fields = {
      {"agent_sequence", std::to_string(agent_sequence)},
      {"command_message_id", "\"" + utils::escape_json(command_message_id) + "\""},
      {"opcode", "\"" + utils::escape_json(opcode) + "\""},
      {"params", params_json},
      {"policy_hash", "\"" + utils::escape_json(policy_hash) + "\""},
      {"request_id", "\"" + utils::escape_json(request_id) + "\""},
      {"timestamp", "\"" + utils::escape_json(timestamp) + "\""}};

  return utils::canonical_object(fields);
}

/**
 * Verify the request signature.
 * Returns true if:
 *   - Signature verification is disabled (KERNEL_REQUIRE_SIGNATURE != 1), OR
 *   - The signature is valid
 *
 * Returns false if signature verification is required and fails.
 */
static bool verify_request_signature(const std::string &req, std::string &error_out)
{
  // Check if signature verification is required
  if (!is_signature_required())
  {
    utils::log_info("signature_verify: signature verification disabled (KERNEL_REQUIRE_SIGNATURE != 1)");
    return true;
  }

  // Extract signature from request
  std::string sig = extract_json_string(req, "signature");
  if (sig.empty())
  {
    // Also check for "sig" as an alias
    sig = extract_json_string(req, "sig");
  }

  if (sig.empty())
  {
    error_out = "SIGNATURE_MISSING";
    utils::log_error("signature_verify: signature field missing from request");
    return false;
  }

  // Build canonical payload
  std::string canonical_payload = build_canonical_request_payload(req);
  utils::log_info("signature_verify: canonical_payload = " + canonical_payload);

  // Verify using Ed25519
  // The public key is loaded from environment (KERNEL_CONTROLLER_PUBKEY_B64) or file
  if (!ed25519_verify_message(canonical_payload, sig, std::string()))
  {
    error_out = "SIGNATURE_INVALID";
    utils::log_error("signature_verify: Ed25519 signature verification failed");
    return false;
  }

  utils::log_info("signature_verify: signature verified successfully");
  return true;
}

/**
 * Create an error response for signature verification failures.
 */
static KernelResponse make_signature_error_response(const std::string &request_id, const std::string &error_code)
{
  KernelResponse resp;
  resp.request_id = request_id.empty() ? "req-unknown" : request_id;
  resp.status = "denied";
  resp.kernel_exec_id = "";
  resp.timestamp = ""; // Will be filled by caller if needed
  resp.result = "signature_verification_failed";
  resp.error_code = 2001; // SIGNATURE_INVALID per spec
  resp.error_message = error_code;
  resp.sig = "";
  return resp;
}

// --- JSON Output Helpers ---

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

          // ============== Signature Verification ==============
          // When KERNEL_REQUIRE_SIGNATURE=1, all requests must be signed.
          // The canonical payload is built from request fields and verified using Ed25519.
          std::string sig_error;
          if (!verify_request_signature(req, sig_error))
          {
            utils::log_error("pipe_server: signature verification failed: " + sig_error);
            KernelResponse resp_err = make_signature_error_response(request_id, sig_error);
            std::string out_err = to_json(resp_err);
            DWORD written_err = 0;
            WriteFile(hPipe, out_err.c_str(), static_cast<DWORD>(out_err.size()), &written_err, NULL);
            FlushFileBuffers(hPipe);
            DisconnectNamedPipe(hPipe);
            CloseHandle(hPipe);
            continue;
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
