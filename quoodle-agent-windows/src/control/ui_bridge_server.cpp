#ifdef _WIN32

#include "ui_bridge_server.hpp"

#include <algorithm>
#include <chrono>
#include <string>
#include <vector>

#include <windows.h>
#include <sddl.h>

#include <nlohmann/json.hpp>

#include "../logging/logger.hpp"

namespace
{
  constexpr const char *kUiBridgePipeName = R"(\\.\pipe\QuoodleAgentUiBridge)";
  constexpr std::size_t kMaxRequestBytes = 1024 * 64;
  constexpr DWORD kReadChunkBytes = 4096;

  std::string now_iso_utc()
  {
    using namespace std::chrono;
    const auto now = system_clock::now();
    const auto tt = system_clock::to_time_t(now);
    std::tm tm{};
#ifdef _WIN32
    gmtime_s(&tm, &tt);
#else
    gmtime_r(&tt, &tm);
#endif
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%04d-%02d-%02dT%02d:%02d:%02dZ",
                  tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
                  tm.tm_hour, tm.tm_min, tm.tm_sec);
    return std::string(buffer);
  }

  bool read_pipe_message(HANDLE pipe, std::string &out)
  {
    out.clear();
    std::vector<char> chunk(kReadChunkBytes);
    DWORD bytes_read = 0;
    while (true)
    {
      const BOOL ok = ReadFile(pipe, chunk.data(), static_cast<DWORD>(chunk.size()), &bytes_read, nullptr);
      if (!ok)
      {
        const DWORD err = GetLastError();
        if (err == ERROR_MORE_DATA)
        {
          if (bytes_read > 0)
          {
            out.append(chunk.data(), chunk.data() + bytes_read);
            if (out.size() > kMaxRequestBytes)
            {
              return false;
            }
          }
          continue;
        }
        if (err == ERROR_BROKEN_PIPE || err == ERROR_PIPE_NOT_CONNECTED)
        {
          return !out.empty();
        }
        return false;
      }

      if (bytes_read == 0)
      {
        return !out.empty();
      }

      out.append(chunk.data(), chunk.data() + bytes_read);
      if (out.size() > kMaxRequestBytes)
      {
        return false;
      }

      // Message-mode pipes return success when one full message has been read.
      // Do not wait for client disconnect; respond immediately.
      return true;
    }
  }

  void write_pipe_message(HANDLE pipe, const std::string &payload)
  {
    DWORD written = 0;
    const BOOL ok = WriteFile(pipe, payload.data(), static_cast<DWORD>(payload.size()), &written, nullptr);
    (void)ok;
    FlushFileBuffers(pipe);
  }
} // namespace

namespace control
{
  UiBridgeServer::UiBridgeServer(StatusProvider status_provider,
                                 ActionHandler sync_now_handler,
                                 ActionHandler reconnect_handler)
      : status_provider_(std::move(status_provider)),
        sync_now_handler_(std::move(sync_now_handler)),
        reconnect_handler_(std::move(reconnect_handler))
  {
  }

  UiBridgeServer::~UiBridgeServer()
  {
    stop();
  }

  bool UiBridgeServer::start()
  {
    bool expected = false;
    if (!running_.compare_exchange_strong(expected, true, std::memory_order_acq_rel))
    {
      return true;
    }

    try
    {
      worker_ = std::thread([this]()
                            { run(); });
      Logger::log(LogLevel::Info, "ui bridge pipe server started");
      return true;
    }
    catch (const std::exception &e)
    {
      running_.store(false, std::memory_order_release);
      Logger::log(LogLevel::Error, std::string("failed to start ui bridge pipe server: ") + e.what());
      return false;
    }
  }

  void UiBridgeServer::stop()
  {
    if (!running_.exchange(false, std::memory_order_acq_rel))
    {
      return;
    }

    wake_listener();
    if (worker_.joinable())
    {
      worker_.join();
    }
    Logger::log(LogLevel::Info, "ui bridge pipe server stopped");
  }

  void UiBridgeServer::wake_listener() const
  {
    HANDLE client = CreateFileA(
        kUiBridgePipeName,
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr);
    if (client != INVALID_HANDLE_VALUE)
    {
      CloseHandle(client);
    }
  }

  std::string UiBridgeServer::handle_request_json(const std::string &request_json) const
  {
    nlohmann::json response = nlohmann::json::object();
    response["ok"] = false;
    response["ts"] = now_iso_utc();

    try
    {
      const auto request = nlohmann::json::parse(request_json);
      const std::string op = request.value("op", "");

      if (op == "status")
      {
        const UiBridgeStatus status = status_provider_ ? status_provider_() : UiBridgeStatus{};
        response["ok"] = true;
        response["op"] = "status";
        response["status"] = {
            {"service_mode", status.service_mode},
            {"communicator_present", status.communicator_present},
            {"connected", status.connected},
            {"connection_state", status.connection_state},
            {"reconnect_attempts", status.reconnect_attempts},
            {"endpoint", status.endpoint},
            {"device_id", status.device_id},
            {"agent_pubkey_b64", status.agent_pubkey_b64},
            {"timestamp_utc", status.timestamp_utc},
        };
        return response.dump();
      }

      if (op == "sync_now")
      {
        std::string reason;
        const bool accepted = sync_now_handler_ ? sync_now_handler_(reason) : false;
        response["ok"] = accepted;
        response["op"] = "sync_now";
        response["accepted"] = accepted;
        response["reason"] = reason;
        return response.dump();
      }

      if (op == "reconnect")
      {
        std::string reason;
        const bool accepted = reconnect_handler_ ? reconnect_handler_(reason) : false;
        response["ok"] = accepted;
        response["op"] = "reconnect";
        response["accepted"] = accepted;
        response["reason"] = reason;
        return response.dump();
      }

      response["error"] = "unknown_op";
      return response.dump();
    }
    catch (const std::exception &e)
    {
      response["error"] = "invalid_request";
      response["reason"] = e.what();
      return response.dump();
    }
  }

  void UiBridgeServer::run()
  {
    PSECURITY_DESCRIPTOR sd = nullptr;
    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = FALSE;

    const BOOL sd_ok = ConvertStringSecurityDescriptorToSecurityDescriptorA(
        "D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;AU)",
        SDDL_REVISION_1,
        &sd,
        nullptr);
    if (sd_ok)
    {
      sa.lpSecurityDescriptor = sd;
    }

    while (running_.load(std::memory_order_acquire))
    {
      HANDLE pipe = CreateNamedPipeA(
          kUiBridgePipeName,
          PIPE_ACCESS_DUPLEX,
          PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
          PIPE_UNLIMITED_INSTANCES,
          65536,
          65536,
          1000,
          sd_ok ? &sa : nullptr);

      if (pipe == INVALID_HANDLE_VALUE)
      {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
        continue;
      }

      const BOOL connected = ConnectNamedPipe(pipe, nullptr)
                                 ? TRUE
                                 : (GetLastError() == ERROR_PIPE_CONNECTED);
      if (!connected)
      {
        CloseHandle(pipe);
        continue;
      }

      if (!running_.load(std::memory_order_acquire))
      {
        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
        break;
      }

      std::string request_json;
      if (read_pipe_message(pipe, request_json))
      {
        const std::string response = handle_request_json(request_json);
        write_pipe_message(pipe, response);
      }

      DisconnectNamedPipe(pipe);
      CloseHandle(pipe);
    }

    if (sd_ok && sd != nullptr)
    {
      LocalFree(sd);
    }
  }
} // namespace control

#endif // _WIN32
