#pragma once

#include <string>
#include <csignal>
#include "../config/config.hpp"
#include "../ws/ws_client.hpp"

/**
 * High-level communicator that manages WebSocket connection lifecycle.
 * Provides automatic reconnection with exponential backoff.
 */
class Communicator
{
public:
  /**
   * Construct with full configuration (preferred).
   */
  explicit Communicator(const AgentConfig &config)
      : client_(config) {}

  /**
   * Legacy constructor for backward compatibility.
   */
  Communicator(const std::string &endpoint, const std::string &device_id)
      : client_(endpoint, device_id) {}

  void set_initial_message(const std::string &msg) { client_.set_initial_message(msg); }

  /**
   * Start with automatic reconnection (blocking).
   * Use this for production deployments.
   */
  void start() { client_.run(); }

  /**
   * Start single connection attempt (legacy behavior).
   * @deprecated Use start() for proper reconnection handling.
   */
  void start_once() { client_.connect_and_run(); }

  /**
   * Request graceful shutdown.
   * Safe to call from signal handlers.
   */
  void shutdown() { client_.shutdown(); }

  /**
   * Check if currently connected.
   */
  bool is_connected() const { return client_.is_connected(); }

  /**
   * Get current connection state.
   */
  ConnectionState state() const { return client_.state(); }

  /**
   * Set callback for connection state changes.
   */
  void on_state_change(WsClient::StateCallback callback)
  {
    client_.on_state_change(std::move(callback));
  }

private:
  WsClient client_;
};
