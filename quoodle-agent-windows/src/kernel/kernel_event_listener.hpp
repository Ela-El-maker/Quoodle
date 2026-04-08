#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <string>
#include <thread>

#ifdef _WIN32
#include <windows.h>
#endif

#include "driver_ioctl.hpp"

struct KernelEvent {
  std::uint64_t event_id{0};
  std::uint32_t event_type{0};
  std::uint64_t timestamp_unix{0};
  std::string payload_json;
};

class KernelEventListener {
public:
  using EventCallback = std::function<void(const KernelEvent &)>;

  KernelEventListener();
  ~KernelEventListener();

  bool start(EventCallback callback);
  void stop();
  bool is_running() const;

private:
  void run();

#ifdef _WIN32
  HANDLE hDevice_{INVALID_HANDLE_VALUE};
#endif
  std::atomic<bool> stop_requested_{false};
  std::atomic<bool> running_{false};
  EventCallback callback_{};
  std::thread worker_{};
};
