#pragma once

#include <atomic>
#include <functional>
#include <random>
#include <string>
#include <cstdint>

#include "../agent_state.hpp"
#include "../config/config.hpp"
#include "../logging/logger.hpp"
#include "../ota/ota_manager.hpp"
#include "../quarantine/quarantine_manager.hpp"
#include "../recovery/recovery_manager.hpp"

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

private:
  AgentConfig config_;
  std::string initial_message_;
  bool heartbeat_sent_{false};
  bool telemetry_sent_{false};
  std::string last_session_id_;
  AgentState state_impl_;
  OTAManager ota_;
  QuarantineManager quarantine_;
  RecoveryManager recovery_;

  // Sequence tracking for replay protection
  std::uint64_t last_command_seq_{0};

  // Reconnection state
  std::atomic<ConnectionState> connection_state_{ConnectionState::Disconnected};
  std::atomic<bool> shutdown_requested_{false};
  std::atomic<std::uint32_t> reconnect_attempts_{0};
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
};
