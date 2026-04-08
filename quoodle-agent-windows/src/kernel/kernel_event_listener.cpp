#include "kernel_event_listener.hpp"
#include "../logging/logger.hpp"

#include <algorithm>
#include <cstring>

KernelEventListener::KernelEventListener() = default;

KernelEventListener::~KernelEventListener() {
  stop();
}

bool KernelEventListener::start(EventCallback callback) {
  if (running_.load(std::memory_order_acquire)) {
    return false;
  }

  stop_requested_.store(false, std::memory_order_release);
  callback_ = std::move(callback);

#ifdef _WIN32
  const char *devicePaths[] = {
      QUOODLE_DEVICE_PATH,
      QUOODLE_DEVICE_PATH_GLOBAL,
      QUOODLE_DEVICE_PATH_NATIVE};
  for (const char *path : devicePaths) {
    hDevice_ = CreateFileA(
        path,
        GENERIC_READ | GENERIC_WRITE,
        0,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        NULL);
    if (hDevice_ != INVALID_HANDLE_VALUE) {
      break;
    }
  }
  if (hDevice_ == INVALID_HANDLE_VALUE) {
    Logger::log(LogLevel::Warn, "kernel event listener: device not available");
    return false;
  }
#else
  return false;
#endif

  running_.store(true, std::memory_order_release);
  worker_ = std::thread(&KernelEventListener::run, this);
  return true;
}

void KernelEventListener::stop() {
  stop_requested_.store(true, std::memory_order_release);
#ifdef _WIN32
  if (hDevice_ != INVALID_HANDLE_VALUE) {
    CancelIoEx(hDevice_, NULL);
  }
#endif
  if (worker_.joinable()) {
    worker_.join();
  }
#ifdef _WIN32
  if (hDevice_ != INVALID_HANDLE_VALUE) {
    CloseHandle(hDevice_);
    hDevice_ = INVALID_HANDLE_VALUE;
  }
#endif
  running_.store(false, std::memory_order_release);
}

bool KernelEventListener::is_running() const {
  return running_.load(std::memory_order_acquire);
}

void KernelEventListener::run() {
#ifdef _WIN32
  OVERLAPPED ov{};
  ov.hEvent = CreateEventA(NULL, TRUE, FALSE, NULL);
  if (!ov.hEvent) {
    Logger::log(LogLevel::Error, "kernel event listener: failed to create wait event");
    running_.store(false, std::memory_order_release);
    return;
  }

  while (!stop_requested_.load(std::memory_order_acquire)) {
    QuoodleKernelEvent evt{};
    DWORD bytesReturned = 0;
    ResetEvent(ov.hEvent);

    BOOL ok = DeviceIoControl(
        hDevice_,
        IOCTL_QUOODLE_WAIT_EVENT,
        NULL,
        0,
        &evt,
        sizeof(evt),
        &bytesReturned,
        &ov);

    if (!ok) {
      DWORD err = GetLastError();
      if (err == ERROR_IO_PENDING) {
        DWORD wait = WaitForSingleObject(ov.hEvent, 500);
        if (wait == WAIT_TIMEOUT) {
          continue;
        }
        if (wait != WAIT_OBJECT_0) {
          break;
        }
        ok = GetOverlappedResult(hDevice_, &ov, &bytesReturned, FALSE);
        if (!ok && stop_requested_.load(std::memory_order_acquire)) {
          break;
        }
      } else if (err == ERROR_OPERATION_ABORTED && stop_requested_.load(std::memory_order_acquire)) {
        break;
      } else {
        Logger::log(LogLevel::Warn, "kernel event listener: DeviceIoControl failed");
        Sleep(200);
        continue;
      }
    }

    if (!ok || bytesReturned < sizeof(QuoodleKernelEvent)) {
      continue;
    }

    KernelEvent out{};
    out.event_id = evt.event_id;
    out.event_type = evt.event_type;
    out.timestamp_unix = evt.timestamp_unix;
    size_t len = evt.payload_length;
    if (len == 0) {
      len = strnlen_s(evt.payload_json, sizeof(evt.payload_json));
    }
    len = std::min(len, sizeof(evt.payload_json) - 1);
    out.payload_json.assign(evt.payload_json, len);

    if (callback_) {
      callback_(out);
    }
  }

  CloseHandle(ov.hEvent);
#endif
  running_.store(false, std::memory_order_release);
}
