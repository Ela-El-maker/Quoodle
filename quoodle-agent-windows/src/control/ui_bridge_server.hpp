#pragma once

#ifdef _WIN32

#include <atomic>
#include <cstdint>
#include <functional>
#include <string>
#include <thread>

namespace control
{
  struct UiBridgeStatus
  {
    bool service_mode{false};
    bool communicator_present{false};
    bool connected{false};
    bool authenticated{false};
    std::string connection_state{"disconnected"};
    std::string auth_state{"disconnected"};
    std::uint32_t reconnect_attempts{0};
    std::string endpoint;
    std::string device_id;
    std::string effective_device_id;
    std::string agent_pubkey_b64;
    std::string timestamp_utc;
  };

  class UiBridgeServer
  {
  public:
    using StatusProvider = std::function<UiBridgeStatus()>;
    using ActionHandler = std::function<bool(std::string &reason_out)>;

    UiBridgeServer(StatusProvider status_provider,
                   ActionHandler sync_now_handler,
                   ActionHandler reconnect_handler);
    ~UiBridgeServer();

    bool start();
    void stop();

  private:
    void run();
    std::string handle_request_json(const std::string &request_json) const;
    void wake_listener() const;

    StatusProvider status_provider_;
    ActionHandler sync_now_handler_;
    ActionHandler reconnect_handler_;
    std::thread worker_;
    std::atomic<bool> running_{false};
  };
} // namespace control

#endif // _WIN32
