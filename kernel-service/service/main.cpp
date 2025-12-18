#include "dispatcher.hpp"
#include "utils/logger.hpp"

#ifdef _WIN32
#include <windows.h>
#endif

#include <iostream>
#include <string>
#include <sstream>
#include <thread>

// --- Helper Functions Moved to Global/Static Scope ---

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

// --- Main Entry Point ---

int main(int argc, char **argv)
{
  // CLI one-shot mode: kernel_service --once <opcode> <request_id>
  if (argc >= 2 && std::string(argv[1]) == "--once")
  {
    const char *allow_fallback = std::getenv("ALLOW_EXEC_FALLBACK");
    if (!(allow_fallback && std::string(allow_fallback) == "1"))
    {
      // FIXED: Changed log_warn to log_error (or you can add log_warn to logger.hpp)
      utils::log_error("--once mode disabled: ALLOW_EXEC_FALLBACK!=1");
    }
    else
    {
      std::string opcode = (argc >= 3) ? argv[2] : std::string();
      std::string request_id = (argc >= 4) ? argv[3] : std::string("req-unknown");

      Dispatcher disp;
      KernelResponse resp;
      if (opcode == "lock_screen")
        resp = disp.handle_lock_screen(request_id);
      else if (opcode == "ping")
        resp = disp.handle_ping(request_id);
      else
        resp = disp.handle_unknown(request_id, opcode);

      std::cout << to_json(resp) << std::endl;
      return 0;
    }
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

            if (hPipe == INVALID_HANDLE_VALUE) {
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
                    if (request_id.empty()) request_id = "req-unknown";

                    KernelResponse resp;
                    if (opcode == "lock_screen") resp = disp.handle_lock_screen(request_id);
                    else if (opcode == "ping")    resp = disp.handle_ping(request_id);
                    else                         resp = disp.handle_unknown(request_id, opcode);

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
