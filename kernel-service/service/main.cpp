#include "dispatcher.hpp"
#include "utils/logger.hpp"

#ifdef _WIN32
#include <windows.h>
#endif

#include <iostream>
#include <string>
#include <sstream>
#include <thread>

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
  oss << "{";
  oss << "\"request_id\":\"" << json_escape(r.request_id) << "\",";
  oss << "\"status\":\"" << json_escape(r.status) << "\",";
  oss << "\"kernel_exec_id\":\"" << json_escape(r.kernel_exec_id) << "\",";
  oss << "\"timestamp\":\"" << json_escape(r.timestamp) << "\",";
  oss << "\"result\":\"" << json_escape(r.result) << "\",";
  oss << "\"error_code\":" << r.error_code << ",";
  oss << "\"error_message\":\"" << json_escape(r.error_message) << "\",";
  oss << "\"sig\":\"" << json_escape(r.sig) << "\"";
  oss << "}";
  return oss.str();
}

int main(int argc, char **argv)
{
  // CLI one-shot mode: kernel_service --once <opcode> <request_id>
  if (argc >= 2 && std::string(argv[1]) == "--once")
  {
    std::string opcode = (argc >= 3) ? argv[2] : std::string();
    std::string request_id = (argc >= 4) ? argv[3] : std::string("req-unknown");
    Dispatcher disp;
    KernelResponse resp;
    if (opcode == "lock_screen")
    {
      resp = disp.handle_lock_screen(request_id);
    }
    else if (opcode == "ping")
    {
      resp = disp.handle_ping(request_id);
    }
    else
    {
      resp = disp.handle_unknown(request_id, opcode);
    }
    std::cout << to_json(resp) << std::endl;
    return 0;
  }

  utils::log_info("KernelService starting (named-pipe server mode)");

#ifdef _WIN32
  // Run a simple named-pipe server to accept JSON requests from local agents.
  auto pipe_server = [&]()
  {
    Dispatcher disp;
    const char *pipeName = "\\\\.\\pipe\\KernelService";

    while (true)
    {
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

      BOOL connected = ConnectNamedPipe(hPipe, NULL) ? TRUE : (GetLastError() == ERROR_PIPE_CONNECTED);
      if (!connected)
      {
        CloseHandle(hPipe);
        continue;
      }

      // Read request (simple, blocking read) with timeout guard
      std::string req;
      {
        char buffer[8192];
        DWORD read = 0;
        auto start = GetTickCount64();
        const uint64_t read_timeout_ms = 5000;
        while (true)
        {
          BOOL ok = ReadFile(hPipe, buffer, sizeof(buffer), &read, NULL);
          if (!ok || read == 0)
            break;
          req.append(buffer, buffer + read);
          if (read < sizeof(buffer))
            break;
          if ((GetTickCount64() - start) > read_timeout_ms)
          {
            utils::log_error("pipe_server: ReadFile timed out for connection");
            break;
          }
        }
      }

      // Minimal JSON extraction helpers
      auto extract_json_string = [&](const std::string &json, const std::string &key) -> std::string
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
      };

      std::string opcode = extract_json_string(req, "opcode");
      std::string request_id = extract_json_string(req, "request_id");
      if (request_id.empty())
        request_id = "req-unknown";

      KernelResponse resp;
      if (opcode == "lock_screen")
      {
        resp = disp.handle_lock_screen(request_id);
      }
      else if (opcode == "ping")
      {
        resp = disp.handle_ping(request_id);
      }
      else
      {
        resp = disp.handle_unknown(request_id, opcode);
      }

      std::string out = to_json(resp);
      DWORD written = 0;
      if (!WriteFile(hPipe, out.c_str(), static_cast<DWORD>(out.size()), &written, NULL))
      {
        utils::log_error("pipe_server: WriteFile failed (err=" + std::to_string(GetLastError()) + ")");
      }
      else
      {
        FlushFileBuffers(hPipe);
      }
      DisconnectNamedPipe(hPipe);
      CloseHandle(hPipe);
    }
  };

  // Run server in foreground (blocking)
  pipe_server();
#else
  utils::log_info("KernelService: named-pipe server only available on Windows in this build.");
#endif

  return 0;
}
