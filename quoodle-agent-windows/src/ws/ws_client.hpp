#pragma once

#include <atomic>
#include <chrono>
#include <functional>
#include <random>
#include <string>
#include <cstdint>
#include <unordered_map>

#include "../agent_state.hpp"
#include "../config/config.hpp"
#include "../logging/logger.hpp"
#include "../ota/ota_manager.hpp"
#include "../quarantine/quarantine_manager.hpp"
#include "../recovery/recovery_manager.hpp"
#include "../telemetry/telemetry_http_client.hpp"
#include "../telemetry/telemetry_queue.hpp"

/**
 * Connection state for tracking reconnection status.
 */
enum class ConnectionState
{
  Disconnected,
  Connecting,
  Connected,
  Reconnecting,
  Failed,  // Max retries exceeded
  Shutdown // Graceful shutdown requested
};

/**
 * WebSocket client with exponential backoff reconnection.
 *
 * Features:
 * - Automatic reconnection on disconnect/error
 * - Exponential backoff with configurable parameters
 * - Jitter to prevent thundering herd
 * - Max retry limiting
 * - Graceful shutdown support
 */
class WsClient
{
public:
  WsClient(const AgentConfig &config);

  /// Legacy constructor for backward compatibility
  WsClient(std::string endpoint, std::string device_id);

  void set_initial_message(const std::string &message);

  /**
   * Start the WebSocket client with automatic reconnection.
   * Blocks until shutdown() is called or max retries exceeded.
   */
  void run();

  /**
   * Legacy method - runs a single connection attempt.
   * @deprecated Use run() instead for proper reconnection handling.
   */
  void connect_and_run();

  /**
   * Request graceful shutdown of the client.
   * Thread-safe, can be called from signal handlers.
   */
  void shutdown();

  /**
   * Check if the client is currently connected.
   */
  bool is_connected() const;

  /**
   * Get current connection state.
   */
  ConnectionState state() const;

  /**
   * Get number of reconnection attempts since last successful connection.
   */
  std::uint32_t reconnect_attempts() const;

  /**
   * Set callback for connection state changes.
   */
  using StateCallback = std::function<void(ConnectionState, const std::string &)>;
  void on_state_change(StateCallback callback);

  /**
   * Request an immediate heartbeat/telemetry sync tick.
   * Thread-safe.
   */
  void request_sync_now();

  /**
   * Request transport reconnect as soon as possible.
   * Thread-safe.
   */
  void request_reconnect();

private:
  struct TelemetryStats
  {
    std::uint64_t sent{0};
    std::uint64_t queued{0};
    std::uint64_t replayed{0};
    std::uint64_t dropped{0};
    std::uint64_t retry_count{0};
    std::uint64_t kernel_sent{0};
    std::uint64_t kernel_queued{0};
    std::uint64_t kernel_replayed{0};
    std::uint64_t kernel_dropped{0};
    std::uint64_t kernel_retry{0};
    std::string last_success_ts;
  };

  AgentConfig config_;
  std::string initial_message_;
  bool heartbeat_sent_{false};
  bool telemetry_sent_{false};
  std::string last_session_id_;
  AgentState state_impl_;
  OTAManager ota_;
  QuarantineManager quarantine_;
  RecoveryManager recovery_;
  TelemetryHttpClient telemetry_http_client_;
  TelemetryQueue telemetry_queue_;
  TelemetryStats telemetry_stats_;
  std::atomic<bool> suspend_http_fallback_{false};
  std::chrono::steady_clock::time_point last_metrics_log_{std::chrono::steady_clock::now()};

  // Sequence tracking for replay protection
  std::uint64_t last_command_seq_{0};
  std::string last_good_app_lock_policy_blob_;

  // Reconnection state
  std::atomic<ConnectionState> connection_state_{ConnectionState::Disconnected};
  std::atomic<bool> shutdown_requested_{false};
  std::atomic<std::uint32_t> reconnect_attempts_{0};
  std::atomic<bool> force_sync_requested_{false};
  std::atomic<bool> force_reconnect_requested_{false};
  std::uint32_t current_delay_ms_{0};

  // Random number generator for jitter
  std::mt19937 rng_;

  // State change callback
  StateCallback state_callback_;

  /**
   * Calculate next backoff delay with jitter.
   */
  std::uint32_t calculate_backoff_delay();

  /**
   * Reset backoff state after successful connection.
   */
  void reset_backoff();

  /**
   * Update connection state and notify callback.
   */
  void set_state(ConnectionState new_state, const std::string &reason = "");

  /**
   * Perform a single connection attempt.
   * @return true if connection was established and ran normally,
   *         false if connection failed or was terminated.
   */
  bool try_connect();

  void run_disconnected_telemetry_tick(bool extended_scope);
  bool send_telemetry_http(const std::string &endpoint_path,
                           const std::string &payload_json,
                           std::string &error_reason,
                           std::string *response_body = nullptr,
                           int *status_code = nullptr);
  void queue_telemetry_payload(const std::string &payload_json, std::int64_t seq, const std::string &reason);
  bool replay_queued_telemetry();
  bool kernel_category_enabled(const std::string &category) const;
  bool kernel_category_sampled(const std::string &category);
  std::string normalize_kernel_payload_json(const std::string &payload_json, std::string &category_out, bool &masked);
  std::unordered_map<std::string, std::uint64_t> kernel_category_seen_;
};
