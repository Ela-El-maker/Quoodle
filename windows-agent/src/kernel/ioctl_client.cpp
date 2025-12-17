#include "ioctl_client.hpp"
#include <random>
#include <sstream>
#include <string>
#include <array>
#include <memory>
#include <cstdio>
#include <cstdlib>

// Small helper: run the kernel-service binary in one-shot mode and capture stdout.
static std::string run_kernel_service_once(const std::string &opcode, const std::string &request_id)
{
  const char *env_path = std::getenv("KERNEL_SERVICE_PATH");
  std::string bin = env_path ? env_path : "../../kernel-service/service/kernel_service";
#ifdef _WIN32
  std::string cmd = '"' + bin + '"';
#else
  std::string cmd = bin;
#endif
  cmd += " --once ";
  cmd += opcode;
  cmd += " ";
  cmd += request_id;

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

// Very small / forgiving JSON extractor: find a string value for a top-level key.
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

KernelExecResult IoctlClient::lock_screen(const std::string &request_id)
{
  std::string out = run_kernel_service_once("lock_screen", request_id);
  if (out.empty())
    return KernelExecResult{request_id, "error", "", "", "", -1, "failed_to_start_service", ""};
  return parse_result_from_json(out);
}

KernelExecResult IoctlClient::ping(const std::string &request_id)
{
  std::string out = run_kernel_service_once("ping", request_id);
  if (out.empty())
    return KernelExecResult{request_id, "error", "", "", "", -1, "failed_to_start_service", ""};
  return this->parse_result_from_json(out);
}
