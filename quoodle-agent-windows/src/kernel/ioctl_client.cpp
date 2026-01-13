#include "ioctl_client.hpp"
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

/**
 * PRIVATE CORE: execute_request
 * Logic for "Pipe First, Process Fallback"
 */
std::string IoctlClient::execute_request(const std::string &opcode, const std::string &request_id)
{
  if (!ensure_connection())
  {
    // Fallback logic remains the same...
#ifdef ENABLE_EXEC_FALLBACK
    return run_kernel_service_once(opcode, request_id);
#endif
    return "";
  }

  std::string req = "{\"opcode\":\"" + opcode + "\",\"request_id\":\"" + request_id + "\"}";
  DWORD written = 0;

#ifdef _WIN32
  if (WriteFile(hPipe, req.c_str(), (DWORD)req.size(), &written, NULL))
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

/**
 * PUBLIC API: lock_screen
 */
KernelExecResult IoctlClient::lock_screen(const std::string &request_id)
{
  std::string json = execute_request("lock_screen", request_id);
  if (json.empty())
    return {request_id, "error", "", "", "", -1, "ipc_failure", ""};
  return parse_result_from_json(json);
}

/**
 * PUBLIC API: ping
 */
KernelExecResult IoctlClient::ping(const std::string &request_id)
{
  std::string json = execute_request("ping", request_id);
  if (json.empty())
    return {request_id, "error", "", "", "", -1, "ipc_failure", ""};
  return parse_result_from_json(json);
}
