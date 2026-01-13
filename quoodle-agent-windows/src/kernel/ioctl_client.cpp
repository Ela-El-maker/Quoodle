#include "ioctl_client.hpp"
#include "../agent_state.hpp"
#include "../crypto/ed25519_sign.hpp"
#include "../crypto/json_canonicalizer.hpp"
#include "../utils/time_utils.hpp"

#include <random>
#include <sstream>
#include <string>
#include <array>
#include <memory>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#ifdef _WIN32
#include <windows.h>
#endif
#include <thread>
#include <chrono>
#include <mutex>

// Thread-safe sequence counter
static std::mutex s_sequence_mutex;
static std::uint64_t s_sequence_counter{0};

/*
 * PRIVATE HELPER: run_kernel_service_once
 * Fallback method that launches the kernel service process directly.
 * This helper is compiled only when ENABLE_EXEC_FALLBACK is enabled at build time.
 */
#ifdef ENABLE_EXEC_FALLBACK
static std::string run_kernel_service_once(const std::string &opcode, const std::string &request_id)
{
  const char *env_path = std::getenv("KERNEL_SERVICE_PATH");
  std::string bin = env_path ? env_path : "../../kernel-service/service/kernel_service";
#ifdef _WIN32
  std::string cmd = '"' + bin + '"';
#else
  std::string cmd = bin;
#endif
  cmd += " --once " + opcode + " " + request_id;

  std::array<char, 4096> buffer{};
  std::string result;
#ifdef _WIN32
  FILE *pipe = _popen(cmd.c_str(), "r");
#else
  FILE *pipe = popen(cmd.c_str(), "r");
#endif
  if (!pipe)
    return {};
  while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr)
  {
    result += buffer.data();
  }
#ifdef _WIN32
  _pclose(pipe);
#else
  pclose(pipe);
#endif
  return result;
}
#endif

/**
 * PRIVATE HELPER: JSON Extractors
 * Manual parsing to avoid heavy library dependencies in the low-level client.
 */
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

static int extract_json_int(const std::string &json, const std::string &key)
{
  std::string needle = '"' + key + '"';
  auto pos = json.find(needle);
  if (pos == std::string::npos)
    return 0;
  auto colon = json.find(':', pos + needle.size());
  if (colon == std::string::npos)
    return 0;
  auto start = colon + 1;
  while (start < json.size() && (json[start] == ' ' || json[start] == '\n' || json[start] == '\r'))
    ++start;
  auto end = start;
  while (end < json.size() && (isdigit((unsigned char)json[end]) || json[end] == '-'))
    ++end;
  if (end == start)
    return 0;
  return std::stoi(json.substr(start, end - start));
}

IoctlClient::~IoctlClient()
{
  disconnect();
}

void IoctlClient::disconnect()
{
#ifdef _WIN32
  if (hPipe != INVALID_HANDLE_VALUE)
  {
    CloseHandle(hPipe);
    hPipe = INVALID_HANDLE_VALUE;
  }
#endif
}

bool IoctlClient::ensure_connection()
{
#ifdef _WIN32
  // 1. Check if already connected
  if (hPipe != INVALID_HANDLE_VALUE)
  {
    // Peek at the pipe to see if it's still alive
    DWORD bytesAvail = 0;
    if (PeekNamedPipe(hPipe, NULL, 0, NULL, &bytesAvail, NULL) || GetLastError() == ERROR_MORE_DATA)
    {
      return true;
    }
    disconnect(); // Connection lost, clean up and retry
  }

  const char *pipeName = "\\\\.\\pipe\\KernelService";

  // 2. Try to connect
  if (WaitNamedPipeA(pipeName, 500))
  {
    hPipe = CreateFileA(pipeName, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
    if (hPipe != INVALID_HANDLE_VALUE)
    {
      // Set pipe to message mode if your service supports it
      DWORD mode = PIPE_READMODE_BYTE;
      SetNamedPipeHandleState(hPipe, &mode, NULL, NULL);
      return true;
    }
  }
#endif
  return false;
}

KernelExecResult IoctlClient::parse_result_from_json(const std::string &json)
{
  KernelExecResult resp;
  resp.request_id = extract_json_string(json, "request_id");
  resp.status = extract_json_string(json, "status");
  resp.kernel_exec_id = extract_json_string(json, "kernel_exec_id");
  resp.timestamp = extract_json_string(json, "timestamp");
  resp.result = extract_json_string(json, "result");
  resp.error_message = extract_json_string(json, "error_message");
  resp.error_code = extract_json_int(json, "error_code");
  resp.sig = extract_json_string(json, "sig");
  return resp;
}

std::uint64_t IoctlClient::next_sequence()
{
  std::lock_guard<std::mutex> lock(s_sequence_mutex);
  return ++s_sequence_counter;
}

std::string IoctlClient::build_canonical_payload(const std::string &request_id, const std::string &timestamp,
                                                 const std::string &opcode, const std::string &params,
                                                 std::uint64_t agent_sequence, const std::string &policy_hash,
                                                 const std::string &command_message_id)
{
  // Build canonical JSON with fields in lexicographic order (A-Z)
  // Fields: agent_sequence, command_message_id, opcode, params, policy_hash, request_id, timestamp
  std::vector<std::pair<std::string, std::string>> fields;
  fields.emplace_back("agent_sequence", std::to_string(agent_sequence));
  fields.emplace_back("command_message_id", "\"" + crypto::escape_json(command_message_id) + "\"");
  fields.emplace_back("opcode", "\"" + crypto::escape_json(opcode) + "\"");
  fields.emplace_back("params", params.empty() ? "{}" : params); // params is already JSON
  fields.emplace_back("policy_hash", "\"" + crypto::escape_json(policy_hash) + "\"");
  fields.emplace_back("request_id", "\"" + crypto::escape_json(request_id) + "\"");
  fields.emplace_back("timestamp", "\"" + crypto::escape_json(timestamp) + "\"");

  return crypto::canonical_object(fields);
}

/**
 * PRIVATE CORE: execute_request
 * Logic for "Pipe First, Process Fallback"
 * Now builds signed JSON request with all required fields.
 */
std::string IoctlClient::execute_request(const std::string &opcode, const std::string &request_id,
                                         const std::string &params_json, const AgentState &state,
                                         const std::string &command_message_id)
{
  if (!ensure_connection())
  {
    // Fallback logic remains the same...
#ifdef ENABLE_EXEC_FALLBACK
    return run_kernel_service_once(opcode, request_id);
#endif
    return "";
  }

  // Generate timestamp and sequence
  std::string timestamp = utils::iso_timestamp();
  std::uint64_t seq = next_sequence();
  std::string policy_hash = state.policy_hash();

  // Build canonical payload for signing
  std::string canonical = build_canonical_payload(request_id, timestamp, opcode, params_json,
                                                  seq, policy_hash, command_message_id);

  // Sign the canonical payload
  std::string signature = ed25519_sign_payload(canonical);

  // Build the full request JSON (includes signature)
  std::ostringstream req;
  req << "{";
  req << "\"request_id\":\"" << crypto::escape_json(request_id) << "\",";
  req << "\"timestamp\":\"" << crypto::escape_json(timestamp) << "\",";
  req << "\"opcode\":\"" << crypto::escape_json(opcode) << "\",";
  req << "\"params\":" << (params_json.empty() ? "{}" : params_json) << ",";
  req << "\"agent_sequence\":" << seq << ",";
  req << "\"policy_hash\":\"" << crypto::escape_json(policy_hash) << "\",";
  req << "\"command_message_id\":\"" << crypto::escape_json(command_message_id) << "\",";
  req << "\"signature\":\"" << crypto::escape_json(signature) << "\"";
  req << "}";

  std::string request_str = req.str();
  DWORD written = 0;

#ifdef _WIN32
  if (WriteFile(hPipe, request_str.c_str(), (DWORD)request_str.size(), &written, NULL))
  {
    std::string out;
    char buf[4096];
    DWORD bytesRead = 0;

    // Read until we find the closing brace of the JSON
    auto startTime = GetTickCount64();
    while (GetTickCount64() - startTime < 2000)
    {
      if (ReadFile(hPipe, buf, sizeof(buf) - 1, &bytesRead, NULL) && bytesRead > 0)
      {
        buf[bytesRead] = '\0';
        out.append(buf);
        if (out.find('}') != std::string::npos)
          return out;
      }
      else
      {
        if (GetLastError() != ERROR_IO_PENDING)
          break;
      }
    }
  }
  // If we reach here, the communication failed or timed out
  disconnect();
#endif
  return "";
}

// Helper to create error response
static KernelExecResult make_error(const std::string &request_id, int code, const std::string &msg)
{
  return {request_id, "error", "", "", "", code, msg, ""};
}

/**
 * PUBLIC API: lock_screen
 */
KernelExecResult IoctlClient::lock_screen(const std::string &request_id, const AgentState &state,
                                          const std::string &command_message_id)
{
  std::string json = execute_request("EXEC_LOCK_SCREEN", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: ping
 */
KernelExecResult IoctlClient::ping(const std::string &request_id, const AgentState &state,
                                   const std::string &command_message_id)
{
  std::string json = execute_request("ping", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: reboot
 */
KernelExecResult IoctlClient::reboot(const std::string &request_id, const AgentState &state,
                                     const std::string &command_message_id)
{
  std::string json = execute_request("EXEC_REBOOT", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: shutdown
 */
KernelExecResult IoctlClient::shutdown(const std::string &request_id, const AgentState &state,
                                       const std::string &command_message_id)
{
  std::string json = execute_request("EXEC_SHUTDOWN", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: logout
 */
KernelExecResult IoctlClient::logout(const std::string &request_id, const AgentState &state,
                                     const std::string &command_message_id)
{
  std::string json = execute_request("EXEC_LOGOUT", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: collect_system_info
 */
KernelExecResult IoctlClient::collect_system_info(const std::string &request_id, const AgentState &state,
                                                  const std::string &command_message_id)
{
  std::string json = execute_request("COLLECT_SYSTEM_INFO", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: get_process_list
 */
KernelExecResult IoctlClient::get_process_list(const std::string &request_id, const AgentState &state,
                                               const std::string &command_message_id)
{
  std::string json = execute_request("GET_PROCESS_LIST", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: validate_update_package
 */
KernelExecResult IoctlClient::validate_update_package(const std::string &request_id, const AgentState &state,
                                                      const std::string &package_path,
                                                      const std::string &command_message_id)
{
  std::string params = "{\"package_path\":\"" + crypto::escape_json(package_path) + "\"}";
  std::string json = execute_request("VALIDATE_UPDATE_PACKAGE", request_id, params, state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: stage_update
 */
KernelExecResult IoctlClient::stage_update(const std::string &request_id, const AgentState &state,
                                           const std::string &version, const std::string &package_path,
                                           const std::string &command_message_id)
{
  std::string params = "{\"version\":\"" + crypto::escape_json(version) +
                       "\",\"package_path\":\"" + crypto::escape_json(package_path) + "\"}";
  std::string json = execute_request("STAGE_UPDATE", request_id, params, state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: commit_update
 */
KernelExecResult IoctlClient::commit_update(const std::string &request_id, const AgentState &state,
                                            const std::string &command_message_id)
{
  std::string json = execute_request("COMMIT_UPDATE", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: rollback_update
 */
KernelExecResult IoctlClient::rollback_update(const std::string &request_id, const AgentState &state,
                                              const std::string &reason,
                                              const std::string &command_message_id)
{
  std::string params = reason.empty() ? "{}" : "{\"reason\":\"" + crypto::escape_json(reason) + "\"}";
  std::string json = execute_request("ROLLBACK_UPDATE", request_id, params, state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: run_attestation
 */
KernelExecResult IoctlClient::run_attestation(const std::string &request_id, const AgentState &state,
                                              const std::string &command_message_id)
{
  std::string json = execute_request("RUN_ATTESTATION", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: run_tamper_check
 */
KernelExecResult IoctlClient::run_tamper_check(const std::string &request_id, const AgentState &state,
                                               const std::string &command_message_id)
{
  std::string json = execute_request("RUN_TAMPER_CHECK", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: self_repair
 */
KernelExecResult IoctlClient::self_repair(const std::string &request_id, const AgentState &state,
                                          const std::string &component,
                                          const std::string &command_message_id)
{
  std::string params = component.empty() ? "{}" : "{\"component\":\"" + crypto::escape_json(component) + "\"}";
  std::string json = execute_request("SELF_REPAIR", request_id, params, state, command_message_id);
  if (json.empty())
    return make_error(request_id, -1, "ipc_failure");
  return parse_result_from_json(json);
}
