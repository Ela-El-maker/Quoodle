#include "ioctl_client.hpp"
#include "../agent_state.hpp"
#include "../crypto/ed25519_sign.hpp"
#include "../crypto/json_canonicalizer.hpp"
#include "../crypto/kernel_response_verifier.hpp"
#include "../logging/logger.hpp"
#include "../utils/time_utils.hpp"
#include "../utils/sha256.hpp"
#include "opcodes/collect_system_info_codec.hpp"
#include "opcodes/opcode_map.hpp"
#include <nlohmann/json.hpp>

#include <sstream>
#include <string>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#ifdef _WIN32
#include <windows.h>
#endif
#include <mutex>
#include <ctime>
#include <chrono>
#include <vector>
#include <algorithm>
#include <cctype>

static std::uint64_t initial_sequence_seed()
{
  const auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                          std::chrono::system_clock::now().time_since_epoch())
                          .count();
  if (now_ms <= 0)
  {
    return 1;
  }
  return static_cast<std::uint64_t>(now_ms);
}

// Thread-safe sequence counter
static std::mutex s_sequence_mutex;
static std::uint64_t s_sequence_counter{initial_sequence_seed()};

// Environment variable to control kernel response signature verification (default: enabled)
static bool is_kernel_response_verification_required()
{
  const char *env = std::getenv("AGENT_REQUIRE_KERNEL_SIGNATURE");
  // Default to enabled (1) unless explicitly disabled.
  if (!env) return true;
  return std::string(env) != "0";
}

static bool is_pipe_fallback_allowed()
{
  const char *env = std::getenv("QUOODLE_ALLOW_PIPE_FALLBACK");
  return env && std::string(env) == "1";
}

static std::string get_driver_hmac_key()
{
  const char *env = std::getenv("QUOODLE_DRIVER_HMAC_KEY");
  if (env && *env)
  {
    return std::string(env);
  }
#ifdef _WIN32
  HKEY key = nullptr;
  constexpr const char *kRegPath = "SYSTEM\\CurrentControlSet\\Services\\QuoodleKernel\\Parameters";
  if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, kRegPath, 0, KEY_READ, &key) == ERROR_SUCCESS)
  {
    char buffer[256] = {};
    DWORD type = 0;
    DWORD size = static_cast<DWORD>(sizeof(buffer));
    if (RegQueryValueExA(key, "HmacKey", nullptr, &type, reinterpret_cast<LPBYTE>(buffer), &size) == ERROR_SUCCESS &&
        (type == REG_SZ || type == REG_EXPAND_SZ) && size > 1)
    {
      RegCloseKey(key);
      return std::string(buffer);
    }
    RegCloseKey(key);
  }
#endif
  return {};
}

static bool is_hex_char(char c)
{
  return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

static unsigned char hex_val(char c)
{
  if (c >= '0' && c <= '9') return static_cast<unsigned char>(c - '0');
  if (c >= 'a' && c <= 'f') return static_cast<unsigned char>(10 + (c - 'a'));
  return static_cast<unsigned char>(10 + (c - 'A'));
}

static std::string hex_to_bytes(const std::string &hex)
{
  if (hex.size() % 2 != 0) return {};
  std::string out;
  out.reserve(hex.size() / 2);
  for (size_t i = 0; i < hex.size(); i += 2)
  {
    if (!is_hex_char(hex[i]) || !is_hex_char(hex[i + 1])) return {};
    out.push_back(static_cast<char>((hex_val(hex[i]) << 4) | hex_val(hex[i + 1])));
  }
  return out;
}

static std::string sha256_raw(const std::string &input)
{
  return hex_to_bytes(sha256_hex(input));
}

static std::string hmac_sha256_raw(const std::string &key, const std::string &message)
{
  constexpr size_t block_size = 64;
  std::string k = key;
  if (k.size() > block_size)
  {
    k = sha256_raw(k);
  }
  if (k.size() < block_size)
  {
    k.resize(block_size, '\0');
  }

  std::string o_key_pad(block_size, '\0');
  std::string i_key_pad(block_size, '\0');
  for (size_t i = 0; i < block_size; ++i)
  {
    unsigned char b = static_cast<unsigned char>(k[i]);
    o_key_pad[i] = static_cast<char>(b ^ 0x5c);
    i_key_pad[i] = static_cast<char>(b ^ 0x36);
  }

  std::string inner = sha256_raw(i_key_pad + message);
  return sha256_raw(o_key_pad + inner);
}

static const char s_b64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static std::string base64_encode_binary(const std::string &input)
{
  std::string output;
  int val = 0, valb = -6;
  for (unsigned char c : input)
  {
    val = (val << 8) + c;
    valb += 8;
    while (valb >= 0)
    {
      output.push_back(s_b64_table[(val >> valb) & 0x3F]);
      valb -= 6;
    }
  }
  if (valb > -6) output.push_back(s_b64_table[((val << 8) >> (valb + 8)) & 0x3F]);
  while (output.size() % 4) output.push_back('=');
  return output;
}

static int b64_index(char c)
{
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}

static bool base64_decode_binary(const std::string &in, std::string &out)
{
  out.clear();
  int val = 0, valb = -8;
  for (char c : in)
  {
    if (c == '=') break;
    int d = b64_index(c);
    if (d < 0) return false;
    val = (val << 6) + d;
    valb += 6;
    if (valb >= 0)
    {
      out.push_back(static_cast<char>((val >> valb) & 0xFF));
      valb -= 8;
    }
  }
  return true;
}

static std::string build_driver_request_canonical(const QuoodleIoctlRequest &req)
{
  std::ostringstream oss;
  auto bounded_len = [](const char *s, size_t cap) -> size_t
  {
    size_t n = 0;
    while (n < cap && s[n] != '\0') ++n;
    return n;
  };
  size_t cmd_len = bounded_len(req.command_message_id, sizeof(req.command_message_id));
  size_t policy_len = bounded_len(req.policy_hash, sizeof(req.policy_hash));
  size_t req_len = bounded_len(req.request_id, sizeof(req.request_id));

  oss << "v1\n";
  oss << "seq=" << req.agent_sequence << "\n";
  oss << "cmd=" << cmd_len << ":" << std::string(req.command_message_id, cmd_len) << "\n";
  oss << "op=" << req.opcode << "\n";
  oss << "params=" << req.params_length << ":" << std::string(req.params_json, req.params_length) << "\n";
  oss << "policy=" << policy_len << ":" << std::string(req.policy_hash, policy_len) << "\n";
  oss << "req=" << req_len << ":" << std::string(req.request_id, req_len) << "\n";
  oss << "ts=" << req.timestamp_unix << "\n";
  return oss.str();
}

static std::string build_driver_response_canonical(const QuoodleIoctlResponse &resp)
{
  std::ostringstream oss;
  auto bounded_len = [](const char *s, size_t cap) -> size_t
  {
    size_t n = 0;
    while (n < cap && s[n] != '\0') ++n;
    return n;
  };
  size_t req_len = bounded_len(resp.request_id, sizeof(resp.request_id));
  size_t kexec_len = bounded_len(resp.kernel_exec_id, sizeof(resp.kernel_exec_id));
  size_t err_len = bounded_len(resp.error_message, sizeof(resp.error_message));
  size_t result_len = std::min(static_cast<size_t>(resp.result_length), sizeof(resp.result_json));
  const std::string result_b64 = base64_encode_binary(std::string(resp.result_json, result_len));

  oss << "v1\n";
  oss << "status=" << resp.status << "\n";
  oss << "error=" << resp.error_code << "\n";
  oss << "kexec=" << kexec_len << ":" << std::string(resp.kernel_exec_id, kexec_len) << "\n";
  oss << "req=" << req_len << ":" << std::string(resp.request_id, req_len) << "\n";
  oss << "result=" << result_len << ":" << result_b64.size() << ":" << result_b64 << "\n";
  oss << "msg=" << err_len << ":" << std::string(resp.error_message, err_len) << "\n";
  oss << "ts=" << resp.timestamp_unix << "\n";
  return oss.str();
}

static bool constant_time_equals(const std::string &a, const std::string &b)
{
  if (a.size() != b.size()) return false;
  unsigned char diff = 0;
  for (size_t i = 0; i < a.size(); ++i) diff |= static_cast<unsigned char>(a[i] ^ b[i]);
  return diff == 0;
}

#ifdef _WIN32
static HANDLE open_quoodle_device_handle()
{
  const char *devicePaths[] = {
      QUOODLE_DEVICE_PATH,
      QUOODLE_DEVICE_PATH_GLOBAL,
      QUOODLE_DEVICE_PATH_NATIVE};

  for (const char *path : devicePaths)
  {
    HANDLE h = CreateFileA(
        path,
        GENERIC_READ | GENERIC_WRITE,
        0,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        NULL);
    if (h != INVALID_HANDLE_VALUE)
    {
      return h;
    }
  }
  return INVALID_HANDLE_VALUE;
}
#endif

static bool sign_driver_request(QuoodleIoctlRequest &req, std::string &error_out)
{
  std::string key = get_driver_hmac_key();
  if (key.empty())
  {
    error_out = "hmac_key_missing";
    return false;
  }

  std::string canonical = build_driver_request_canonical(req);
  std::string mac_raw = hmac_sha256_raw(key, canonical);
  if (mac_raw.size() != QUOODLE_HMAC_SHA256_BYTES)
  {
    error_out = "hmac_compute_failed";
    return false;
  }

  std::string sig_b64 = base64_encode_binary(mac_raw);
  if (sig_b64.size() >= sizeof(req.signature_b64))
  {
    error_out = "signature_too_long";
    return false;
  }

  std::memset(req.signature_b64, 0, sizeof(req.signature_b64));
  std::memcpy(req.signature_b64, sig_b64.data(), sig_b64.size());
  req.signature_length = static_cast<uint32_t>(sig_b64.size());
  return true;
}

static bool verify_driver_response_signature(const QuoodleIoctlResponse &resp, std::string &error_out)
{
  if (!is_kernel_response_verification_required())
  {
    return true;
  }

  if (resp.signature_length == 0 || resp.signature_length >= QUOODLE_MAX_SIG_B64)
  {
    error_out = "signature_missing";
    return false;
  }
  if (resp.signature_b64[resp.signature_length] != '\0')
  {
    error_out = "signature_bad_payload";
    return false;
  }

  std::string key = get_driver_hmac_key();
  if (key.empty())
  {
    error_out = "hmac_key_missing";
    return false;
  }

  std::string provided;
  if (!base64_decode_binary(std::string(resp.signature_b64, resp.signature_length), provided))
  {
    error_out = "signature_decode_failed";
    return false;
  }
  if (provided.size() != QUOODLE_HMAC_SHA256_BYTES)
  {
    error_out = "signature_invalid_length";
    return false;
  }

  std::string canonical = build_driver_response_canonical(resp);
  std::string expected = hmac_sha256_raw(key, canonical);
  if (!constant_time_equals(expected, provided))
  {
    error_out = "signature_invalid";
    return false;
  }
  return true;
}

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
  if (hDevice != INVALID_HANDLE_VALUE)
  {
    CloseHandle(hDevice);
    hDevice = INVALID_HANDLE_VALUE;
  }
  useDevice = false;
#endif
}

bool IoctlClient::ensure_connection()
{
#ifdef _WIN32
  last_transport_error_code_ = -1;
  last_transport_error_message_ = "ipc_failure";
  last_transport_win32_error_ = 0;

  // Prefer kernel driver if enabled and available.
  const char *preferDriver = std::getenv("QUOODLE_USE_KERNEL_DRIVER");
  bool allowDriver = preferDriver && std::string(preferDriver) != "0";
  if (allowDriver)
  {
    if (hDevice != INVALID_HANDLE_VALUE)
    {
      useDevice = true;
      return true;
    }
    hDevice = open_quoodle_device_handle();
    if (hDevice != INVALID_HANDLE_VALUE)
    {
      useDevice = true;
      return true;
    }

    if (!is_pipe_fallback_allowed())
    {
      useDevice = true;
      last_transport_error_code_ = 4101;
      last_transport_error_message_ = "driver_unavailable_fail_closed";
      last_transport_win32_error_ = 0;
      Logger::log(LogLevel::Error, "Kernel driver unavailable and fallback disabled");
      return false;
    }
    Logger::log(LogLevel::Warn, "Kernel driver unavailable; using explicit pipe fallback override");
  }

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
      useDevice = false;
      return true;
    }
  }

  if (allowDriver && is_pipe_fallback_allowed())
  {
    last_transport_error_code_ = 4102;
    last_transport_error_message_ = "driver_and_pipe_unavailable";
    last_transport_win32_error_ = 0;
  }
#endif
  return false;
}

KernelExecResult IoctlClient::parse_result_from_json(const std::string &json)
{
  KernelExecResult resp;
  try
  {
    const auto parsed = nlohmann::json::parse(json);
    resp.request_id = parsed.value("request_id", "");
    resp.status = parsed.value("status", "");
    resp.kernel_exec_id = parsed.value("kernel_exec_id", "");
    resp.timestamp = parsed.value("timestamp", "");
    resp.error_message = parsed.value("error_message", "");
    resp.error_code = parsed.value("error_code", 0);
    if (parsed.contains("result"))
    {
      const auto &result = parsed["result"];
      if (result.is_string())
      {
        resp.result = result.get<std::string>();
      }
      else if (result.is_null())
      {
        resp.result.clear();
      }
      else
      {
        resp.result = result.dump();
      }
    }
    resp.sig = parsed.value("sig", "");
    if (resp.sig.empty())
    {
      resp.sig = parsed.value("signature", "");
    }
    return resp;
  }
  catch (const std::exception &)
  {
    // Fallback parser for malformed/legacy responses.
  }

  resp.request_id = extract_json_string(json, "request_id");
  resp.status = extract_json_string(json, "status");
  resp.kernel_exec_id = extract_json_string(json, "kernel_exec_id");
  resp.timestamp = extract_json_string(json, "timestamp");
  resp.result = extract_json_string(json, "result");
  resp.error_message = extract_json_string(json, "error_message");
  resp.error_code = extract_json_int(json, "error_code");
  resp.sig = extract_json_string(json, "sig");
  if (resp.sig.empty())
  {
    resp.sig = extract_json_string(json, "signature");
  }
  return resp;
}

bool IoctlClient::using_driver_transport() const
{
#ifdef _WIN32
  return useDevice && hDevice != INVALID_HANDLE_VALUE;
#else
  return false;
#endif
}

bool IoctlClient::using_pipe_transport() const
{
#ifdef _WIN32
  return !useDevice && hPipe != INVALID_HANDLE_VALUE;
#else
  return false;
#endif
}

int IoctlClient::last_transport_error_code() const
{
  return last_transport_error_code_;
}

std::string IoctlClient::last_transport_error_message() const
{
  return last_transport_error_message_;
}

int IoctlClient::last_transport_win32_error() const
{
  return last_transport_win32_error_;
}

/**
 * Verify kernel response signature.
 * Returns true if verification passes or is disabled.
 * If verification fails, modifies resp to indicate the error.
 */
static bool verify_kernel_response_signature(const std::string &json, KernelExecResult &resp)
{
  if (!is_kernel_response_verification_required())
  {
    Logger::log(LogLevel::Debug, "Kernel response signature verification disabled");
    return true;
  }

  auto verify_result = crypto::verify_kernel_response(json, "");
  if (!verify_result.valid)
  {
    Logger::log(LogLevel::Warn, "Kernel response signature verification failed: " +
                                    verify_result.error_code + " - " + verify_result.error_message);

    // Preserve the request_id but mark as verification failure
    resp.status = "error";
    resp.error_code = 2001; // SIGNATURE_INVALID per KernelErrorCodes
    resp.error_message = "kernel_signature_" + verify_result.error_code;
    resp.result = "";
    return false;
  }

  Logger::log(LogLevel::Debug, "Kernel response signature verified successfully");
  return true;
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

static KernelExecResult parse_device_response(const QuoodleIoctlResponse &resp, QuoodleOpcode expected_opcode)
{
  KernelExecResult result;
  const size_t raw_len = std::min(static_cast<size_t>(resp.result_length), sizeof(resp.result_json));
  result.request_id = resp.request_id;
  result.status = resp.status == 0 ? "ok" : "error";
  result.kernel_exec_id = resp.kernel_exec_id;
  result.timestamp = std::to_string(resp.timestamp_unix);
  if (expected_opcode == QOP_EXEC_COLLECT_SYSTEM_INFO)
  {
    std::string translated_json;
    if (kernel::opcodes::TryTranslateCollectSystemInfoBinaryResult(resp, translated_json))
    {
      result.result = translated_json;
    }
    else
    {
      std::string raw(resp.result_json, raw_len);
      const size_t null_pos = raw.find('\0');
      if (null_pos != std::string::npos)
      {
        raw.resize(null_pos);
      }
      result.result = raw;
    }
  }
  else
  {
    std::string raw(resp.result_json, raw_len);
    const size_t null_pos = raw.find('\0');
    if (null_pos != std::string::npos)
    {
      raw.resize(null_pos);
    }
    result.result = raw;
  }
  result.error_code = static_cast<int>(resp.error_code);
  result.error_message = resp.error_message;
  const size_t sig_len = std::min(static_cast<size_t>(resp.signature_length), sizeof(resp.signature_b64) - 1);
  result.sig = std::string(resp.signature_b64, sig_len);
  return result;
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
  last_transport_error_code_ = -1;
  last_transport_error_message_ = "ipc_failure";
  last_transport_win32_error_ = 0;

  if (!ensure_connection())
  {
    // Fallback logic remains the same...
#ifdef ENABLE_EXEC_FALLBACK
    if (last_transport_error_code_ == 4101)
      return {};
    return run_kernel_service_once(opcode, request_id);
#endif
    return "";
  }

  if (useDevice && hDevice != INVALID_HANDLE_VALUE)
  {
    QuoodleIoctlRequest req{};
    req.version = QUOODLE_IOCTL_VERSION;
    req.opcode = static_cast<uint32_t>(kernel::opcodes::MapOpcodeToCode(opcode));
    req.flags = 0;
    req.agent_sequence = next_sequence();
    req.timestamp_unix = static_cast<uint64_t>(std::time(nullptr));
    std::strncpy(req.request_id, request_id.c_str(), sizeof(req.request_id) - 1);
    std::string policy_hash = state.policy_hash();
    std::strncpy(req.policy_hash, policy_hash.c_str(), sizeof(req.policy_hash) - 1);
    std::strncpy(req.command_message_id, command_message_id.c_str(), sizeof(req.command_message_id) - 1);
    if (!params_json.empty())
    {
      req.params_length = static_cast<uint32_t>(std::min(params_json.size(), sizeof(req.params_json) - 1));
      std::memcpy(req.params_json, params_json.data(), req.params_length);
      req.params_json[req.params_length] = '\0';
    }
    else
    {
      req.params_length = 0;
      req.params_json[0] = '\0';
    }

    std::string sign_error;
    if (!sign_driver_request(req, sign_error))
    {
      last_transport_error_code_ = QERR_SIGNATURE_INVALID;
      last_transport_error_message_ = "driver_request_" + sign_error;
      last_transport_win32_error_ = 0;
      Logger::log(LogLevel::Error, "Failed to sign driver request: " + sign_error);
      return "";
    }

    QuoodleIoctlResponse resp{};
    DWORD bytesReturned = 0;
    BOOL ok = DeviceIoControl(
        hDevice,
        IOCTL_QUOODLE_EXECUTE,
        &req,
        sizeof(req),
        &resp,
        sizeof(resp),
        &bytesReturned,
        NULL);
    if (!ok)
    {
      const DWORD win32_error = GetLastError();
      last_transport_error_code_ = 4103;
      last_transport_win32_error_ = static_cast<int>(win32_error);
      last_transport_error_message_ = "driver_ioctl_failure_win32_" + std::to_string(win32_error);
      Logger::log(LogLevel::Error, "Driver IOCTL failed. win32_error=" + std::to_string(win32_error) +
                                       " bytesReturned=" + std::to_string(bytesReturned));
      disconnect();
      return "";
    }
    if (bytesReturned < sizeof(QuoodleIoctlResponse))
    {
      last_transport_error_code_ = 4103;
      last_transport_win32_error_ = 0;
      last_transport_error_message_ = "driver_ioctl_short_read_" + std::to_string(bytesReturned);
      Logger::log(LogLevel::Error, "Driver IOCTL returned short response. bytesReturned=" + std::to_string(bytesReturned) +
                                       " expected=" + std::to_string(sizeof(QuoodleIoctlResponse)));
      disconnect();
      return "";
    }

    std::string verify_error;
    if (!verify_driver_response_signature(resp, verify_error))
    {
      last_transport_error_code_ = (verify_error == "signature_missing") ? QERR_SIGNATURE_MISSING : QERR_SIGNATURE_INVALID;
      last_transport_error_message_ = "kernel_signature_" + verify_error;
      last_transport_win32_error_ = 0;
      Logger::log(LogLevel::Warn, "Kernel driver response signature verification failed: " + verify_error);
      return "";
    }

    KernelExecResult result = parse_device_response(resp, static_cast<QuoodleOpcode>(req.opcode));
    // Serialize minimal JSON so existing parsing path can be reused.
    std::ostringstream oss;
    oss << "{";
    oss << "\"request_id\":\"" << crypto::escape_json(result.request_id) << "\",";
    oss << "\"status\":\"" << crypto::escape_json(result.status) << "\",";
    oss << "\"kernel_exec_id\":\"" << crypto::escape_json(result.kernel_exec_id) << "\",";
    oss << "\"timestamp\":\"" << crypto::escape_json(result.timestamp) << "\",";
    oss << "\"result\":\"" << crypto::escape_json(result.result) << "\",";
    oss << "\"error_code\":" << result.error_code << ",";
    oss << "\"error_message\":\"" << crypto::escape_json(result.error_message) << "\",";
    oss << "\"sig\":\"" << crypto::escape_json(result.sig) << "\"";
    oss << "}";
    return oss.str();
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
  last_transport_error_code_ = -1;
  last_transport_error_message_ = "pipe_timeout_or_failure";
  last_transport_win32_error_ = 0;
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
 * Helper to parse and verify kernel response.
 * If verification is enabled and fails, returns error result.
 */
KernelExecResult IoctlClient::parse_and_verify_response(const std::string &json, const std::string &request_id)
{
  KernelExecResult resp = parse_result_from_json(json);

  // Driver-mode responses are already verified at IOCTL boundary using HMAC.
  if (useDevice)
  {
    return resp;
  }

  // Pipe-mode responses continue using existing Ed25519 verifier.
  if (!verify_kernel_response_signature(json, resp))
  {
    // resp has already been modified by verify_kernel_response_signature
    // but ensure request_id is preserved
    resp.request_id = request_id;
    return resp;
  }

  return resp;
}

/**
 * PUBLIC API: collect_system_info
 */
KernelExecResult IoctlClient::collect_system_info(const std::string &request_id, const AgentState &state,
                                                  const std::string &command_message_id,
                                                  const std::string &params_json)
{
  const std::string effective_params = params_json.empty() ? "{}" : params_json;
  std::string json = execute_request("COLLECT_SYSTEM_INFO", request_id, effective_params, state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}

KernelExecResult IoctlClient::capture_screenshot_authorize(const std::string &request_id, const AgentState &state,
                                                           const std::string &command_message_id,
                                                           const std::string &params_json)
{
  const std::string effective_params = params_json.empty() ? "{}" : params_json;
  std::string json = execute_request("CAPTURE_SCREENSHOT", request_id, effective_params, state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}

/**
 * PUBLIC API: get_process_list
 */
KernelExecResult IoctlClient::get_process_list(const std::string &request_id, const AgentState &state,
                                               const std::string &command_message_id)
{
  std::string json = execute_request("LIST_PROCESSES", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}

KernelExecResult IoctlClient::list_services(const std::string &request_id, const AgentState &state,
                                            const std::string &command_message_id)
{
  std::string json = execute_request("LIST_SERVICES", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}

KernelExecResult IoctlClient::list_connections(const std::string &request_id, const AgentState &state,
                                               const std::string &command_message_id)
{
  std::string json = execute_request("LIST_CONNECTIONS", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}

KernelExecResult IoctlClient::list_mounts(const std::string &request_id, const AgentState &state,
                                          const std::string &command_message_id)
{
  std::string json = execute_request("LIST_MOUNTS", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}

KernelExecResult IoctlClient::network_info(const std::string &request_id, const AgentState &state,
                                           const std::string &command_message_id)
{
  std::string json = execute_request("NETWORK_INFO", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}

KernelExecResult IoctlClient::get_active_window(const std::string &request_id, const AgentState &state,
                                                const std::string &command_message_id)
{
  std::string json = execute_request("GET_ACTIVE_WINDOW", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}

KernelExecResult IoctlClient::list_files(const std::string &request_id, const AgentState &state,
                                         const std::string &params_json,
                                         const std::string &command_message_id)
{
  const std::string effective_params = params_json.empty() ? "{}" : params_json;
  std::string json = execute_request("LIST_FILES", request_id, effective_params, state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}

KernelExecResult IoctlClient::download_file(const std::string &request_id, const AgentState &state,
                                            const std::string &params_json,
                                            const std::string &command_message_id)
{
  const std::string effective_params = params_json.empty() ? "{}" : params_json;
  std::string json = execute_request("DOWNLOAD_FILE", request_id, effective_params, state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
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
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
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
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}

/**
 * PUBLIC API: commit_update
 */
KernelExecResult IoctlClient::commit_update(const std::string &request_id, const AgentState &state,
                                            const std::string &command_message_id)
{
  std::string json = execute_request("COMMIT_UPDATE", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
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
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}

/**
 * PUBLIC API: run_attestation
 */
KernelExecResult IoctlClient::run_attestation(const std::string &request_id, const AgentState &state,
                                              const std::string &command_message_id)
{
  std::string json = execute_request("RUN_ATTESTATION", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}

/**
 * PUBLIC API: run_tamper_check
 */
KernelExecResult IoctlClient::run_tamper_check(const std::string &request_id, const AgentState &state,
                                               const std::string &command_message_id)
{
  std::string json = execute_request("RUN_TAMPER_CHECK", request_id, "{}", state, command_message_id);
  if (json.empty())
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
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
    return make_error(request_id, last_transport_error_code_, last_transport_error_message_);
  return parse_and_verify_response(json, request_id);
}
