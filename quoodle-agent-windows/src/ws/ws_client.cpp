#include "ws_client.hpp"

#include <chrono>
#include <iostream>
#include <thread>
#include <unordered_map>
#include <algorithm>
#include <cmath>

#include <ixwebsocket/IXNetSystem.h>
#include <ixwebsocket/IXWebSocket.h>
#include <nlohmann/json.hpp>

#include "../kernel/ioctl_client.hpp"
#include "../crypto/command_verifier.hpp"
#include "ws_protocol.hpp"

// Environment variable to control signature verification (default: enabled)
static bool is_signature_verification_required()
{
  const char *env = std::getenv("AGENT_REQUIRE_COMMAND_SIGNATURE");
  // Default to enabled (1) unless explicitly disabled
  if (!env) {
    static bool logged = false;
    if (!logged) {
        Logger::log(LogLevel::Warn, "AGENT_REQUIRE_COMMAND_SIGNATURE not set. Defaulting to ENABLED.");
        logged = true;
    }
    return true;
  }
  
  bool required = std::string(env) != "0";
  static bool logged = false;
    if (!logged) {
        Logger::log(LogLevel::Info, std::string("Signature verification is ") + (required ? "REQUIRED" : "DISABLED"));
        logged = true;
    }
  return required;
}

WsClient::WsClient(const AgentConfig &config)
    : config_(config), state_impl_(config.device_id), current_delay_ms_(config.reconnection.initial_delay_ms), rng_(std::random_device{}())
{
}

WsClient::WsClient(std::string endpoint, std::string device_id)
    : state_impl_(device_id), rng_(std::random_device{}())
{
  config_.endpoint = std::move(endpoint);
  config_.device_id = std::move(device_id);
  current_delay_ms_ = config_.reconnection.initial_delay_ms;
}

void WsClient::set_initial_message(const std::string &message)
{
  initial_message_ = message;
}

void WsClient::shutdown()
{
  shutdown_requested_.store(true, std::memory_order_release);
  set_state(ConnectionState::Shutdown, "shutdown requested");
}

bool WsClient::is_connected() const
{
  return connection_state_.load(std::memory_order_acquire) == ConnectionState::Connected;
}

ConnectionState WsClient::state() const
{
  return connection_state_.load(std::memory_order_acquire);
}

std::uint32_t WsClient::reconnect_attempts() const
{
  return reconnect_attempts_.load(std::memory_order_acquire);
}

void WsClient::on_state_change(StateCallback callback)
{
  state_callback_ = std::move(callback);
}

void WsClient::set_state(ConnectionState new_state, const std::string &reason)
{
  auto old_state = connection_state_.exchange(new_state, std::memory_order_acq_rel);
  if (old_state != new_state)
  {
    std::string state_name;
    switch (new_state)
    {
    case ConnectionState::Disconnected:
      state_name = "disconnected";
      break;
    case ConnectionState::Connecting:
      state_name = "connecting";
      break;
    case ConnectionState::Connected:
      state_name = "connected";
      break;
    case ConnectionState::Reconnecting:
      state_name = "reconnecting";
      break;
    case ConnectionState::Failed:
      state_name = "failed";
      break;
    case ConnectionState::Shutdown:
      state_name = "shutdown";
      break;
    }

    std::string log_msg = "connection state: " + state_name;
    if (!reason.empty())
    {
      log_msg += " (" + reason + ")";
    }
    Logger::log(LogLevel::Info, log_msg);

    if (state_callback_)
    {
      state_callback_(new_state, reason);
    }
  }
}

std::uint32_t WsClient::calculate_backoff_delay()
{
  // Apply exponential backoff
  auto delay = current_delay_ms_;

  // Add jitter: delay * (1 - jitter_factor) to delay * (1 + jitter_factor)
  if (config_.reconnection.jitter_factor > 0.0)
  {
    std::uniform_real_distribution<double> dist(
        1.0 - config_.reconnection.jitter_factor,
        1.0 + config_.reconnection.jitter_factor);
    delay = static_cast<std::uint32_t>(delay * dist(rng_));
  }

  // Update delay for next attempt (capped at max)
  current_delay_ms_ = std::min(
      static_cast<std::uint32_t>(current_delay_ms_ * config_.reconnection.backoff_multiplier),
      config_.reconnection.max_delay_ms);

  return delay;
}

void WsClient::reset_backoff()
{
  current_delay_ms_ = config_.reconnection.initial_delay_ms;
  reconnect_attempts_.store(0, std::memory_order_release);
}

void WsClient::run()
{
  ix::initNetSystem();

  Logger::log(LogLevel::Info, "starting WebSocket client with reconnection support");
  Logger::log(LogLevel::Debug, "reconnection config: initial_delay=" +
                                   std::to_string(config_.reconnection.initial_delay_ms) + "ms, max_delay=" +
                                   std::to_string(config_.reconnection.max_delay_ms) + "ms, multiplier=" +
                                   std::to_string(config_.reconnection.backoff_multiplier));

  while (!shutdown_requested_.load(std::memory_order_acquire))
  {
    // Check max retries
    auto attempts = reconnect_attempts_.load(std::memory_order_acquire);
    if (config_.reconnection.max_retries > 0 && attempts >= config_.reconnection.max_retries)
    {
      set_state(ConnectionState::Failed, "max retries exceeded (" +
                                             std::to_string(attempts) + "/" +
                                             std::to_string(config_.reconnection.max_retries) + ")");
      break;
    }

    // Attempt connection
    bool success = try_connect();

    if (shutdown_requested_.load(std::memory_order_acquire))
    {
      break;
    }

    if (success && config_.reconnection.reset_on_success)
    {
      reset_backoff();
    }

    // Calculate delay before next attempt
    auto delay = calculate_backoff_delay();
    reconnect_attempts_.fetch_add(1, std::memory_order_acq_rel);

    set_state(ConnectionState::Reconnecting,
              "attempt " + std::to_string(reconnect_attempts_.load()) +
                  ", waiting " + std::to_string(delay) + "ms");

    // Sleep with periodic shutdown checks
    auto remaining = delay;
    const std::uint32_t check_interval = 100; // Check every 100ms
    while (remaining > 0 && !shutdown_requested_.load(std::memory_order_acquire))
    {
      auto sleep_time = std::min(remaining, check_interval);
      std::this_thread::sleep_for(std::chrono::milliseconds(sleep_time));
      remaining -= sleep_time;
    }
  }

  Logger::log(LogLevel::Info, "WebSocket client stopped");
}

bool WsClient::try_connect()
{
  set_state(ConnectionState::Connecting);

  ix::WebSocket socket;
  socket.setUrl(config_.endpoint);

  // Configure connection timeout
  ix::WebSocketPerMessageDeflateOptions deflateOptions;
  socket.setPerMessageDeflateOptions(deflateOptions);

  std::atomic<bool> connection_opened{false};
  std::atomic<bool> connection_closed{false};
  std::atomic<bool> connection_error{false};
  std::string close_reason;

  // Reset per-connection state
  heartbeat_sent_ = false;
  telemetry_sent_ = false;

  socket.setOnMessageCallback([&](const ix::WebSocketMessagePtr &msg)
                              {
        if (msg->type == ix::WebSocketMessageType::Open) {
            connection_opened.store(true, std::memory_order_release);
            set_state(ConnectionState::Connected);
            
            // Reset backoff on successful connection
            if (config_.reconnection.reset_on_success) {
                reset_backoff();
            }
            
            Logger::log(LogLevel::Info, "connected, sending AUTH");
            socket.sendText(initial_message_);
            
        } else if (msg->type == ix::WebSocketMessageType::Message) {
            Logger::log(LogLevel::Debug, std::string("received: ") + msg->str);
            try {
                auto parsed = nlohmann::json::parse(msg->str);
                std::string mtype = parsed.value("type", "");
                if (mtype == "AUTH_ACK") {
                    std::string session_id = parsed["body"].value("session_id", "");
                    if (!session_id.empty()) {
                        last_session_id_ = session_id;
                        state_impl_.set_session_id(session_id);
                        if (!heartbeat_sent_) {
                            auto hb = build_signed_heartbeat_json(config_.device_id, session_id, "alive", 120, "ok");
                            socket.sendText(hb);
                            heartbeat_sent_ = true;
                        }
                        if (!telemetry_sent_) {
                            auto tel = build_signed_telemetry_json(config_.device_id, session_id);
                            socket.sendText(tel);
                            telemetry_sent_ = true;
                        }
                    }
                } else if (mtype == "POLICY_UPDATE") {
                    auto body = parsed["body"];
                    std::string policy_hash = body.value("policy_hash", "");
                    state_impl_.set_policy_hash(policy_hash);
                    Logger::log(LogLevel::Info, "policy updated: " + policy_hash);
                } else if (mtype == "COMMAND_DELIVERY") {
                    std::string session_id = parsed.value("session_id", "");
                    auto body = parsed["body"];
                    auto envelope = body["command_envelope"];
                    std::string command_message_id = envelope.value("message_id", "");
                    std::string trace_id = envelope.value("trace_id", "");
                    std::string method = envelope["body"].value("method", "");
                    std::string policy_hash = envelope["meta"].value("policy_hash", "");

                    if (!session_id.empty() && !command_message_id.empty()) {
                        // Verify command envelope signature before processing
                        if (is_signature_verification_required()) {
                            std::string envelope_str = envelope.dump();
                            auto verify_result = crypto::verify_command_envelope(envelope_str, last_command_seq_, "");
                            
                            if (!verify_result.valid) {
                                Logger::log(LogLevel::Warn, "COMMAND_DELIVERY signature verification failed: " + 
                                           verify_result.error_code + " - " + verify_result.error_message);
                                
                                // Send rejection ACK with reason
                                auto rejected_ack = build_command_ack_json(config_.device_id, session_id, command_message_id, 
                                                                           "rejected", verify_result.error_code);
                                socket.sendText(rejected_ack);
                                
                                // Send error result
                                int error_code = 4003;
                                if (verify_result.error_code == "TTL_EXPIRED") error_code = 4005;
                                else if (verify_result.error_code == "SEQ_REPLAY") error_code = 4006;
                                
                                auto denied = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                        trace_id, "failed", verify_result.error_code,
                                                                        verify_result.error_message, "", "", error_code, "");
                                socket.sendText(denied);
                                return;
                            }
                            
                            // Update last sequence on successful verification
                            std::uint64_t new_seq = envelope.value("seq", static_cast<std::uint64_t>(0));
                            if (new_seq > last_command_seq_) {
                                last_command_seq_ = new_seq;
                            }
                            
                            Logger::log(LogLevel::Debug, "COMMAND_DELIVERY signature verified successfully");
                        }
                        
                        auto ack = build_command_ack_json(config_.device_id, session_id, command_message_id, "received", "");
                        socket.sendText(ack);

                        if (quarantine_.is_quarantined() && !quarantine_.is_allowed(method)) {
                            auto denied = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                    trace_id, "failed", "denied",
                                                                    "quarantined", "", "", 4001,
                                                                    quarantine_.reason());
                            socket.sendText(denied);
                            return;
                        }

                        if (!policy_hash.empty() && !state_impl_.policy_hash().empty() && policy_hash != state_impl_.policy_hash()) {
                            auto denied = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                    trace_id, "failed", "policy_mismatch",
                                                                    "policy hash mismatch", "", "", 4002, "");
                            socket.sendText(denied);
                            return;
                        }

                        IoctlClient ioctl;
                        if (method == "lock_screen") {
                            auto res = ioctl.lock_screen(command_message_id, state_impl_, command_message_id);
                            auto result_msg = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                        trace_id, "completed", "ok", "lock_screen done",
                                                                        "", "", res.error_code, res.error_message);
                            socket.sendText(result_msg);
                        } else if (method == "ping") {
                            auto res = ioctl.ping(command_message_id, state_impl_, command_message_id);
                            auto result_msg = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                        trace_id, "completed", "ok", res.result,
                                                                        "", "", res.error_code, res.error_message);
                            socket.sendText(result_msg);
                        } else {
                            auto not_supported = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                           trace_id, "failed", "unsupported",
                                                                           "command not supported", "", "", 4004, "");
                            socket.sendText(not_supported);
                        }
                    }
                } else if (mtype == "UPDATE_ANNOUNCE") {
                    std::string session_id = parsed.value("session_id", "");
                    auto body = parsed["body"];
                    std::string release_id = body.value("release_id", "");
                    std::string version = body.value("version", "");
                    if (!session_id.empty() && !release_id.empty()) {
                        std::unordered_map<std::string, std::string> manifest;
                        manifest["release_id"] = release_id;
                        manifest["version"] = version;
                        ota_.set_manifest(manifest);
                        state_impl_.set_release(release_id);
                        auto status_msg = build_update_status_json(
                            config_.device_id, session_id, release_id, "precheck", version, 0, "acknowledged", 0, "", "");
                        socket.sendText(status_msg);
                    }
                }
            } catch (const std::exception& e) {
                Logger::log(LogLevel::Error, std::string("parse error: ") + e.what());
            }
            
        } else if (msg->type == ix::WebSocketMessageType::Error) {
            connection_error.store(true, std::memory_order_release);
            close_reason = msg->errorInfo.reason;
            Logger::log(LogLevel::Error, std::string("ws error: ") + msg->errorInfo.reason);
            
        } else if (msg->type == ix::WebSocketMessageType::Close) {
            connection_closed.store(true, std::memory_order_release);
            close_reason = "code=" + std::to_string(msg->closeInfo.code) + 
                          ", reason=" + msg->closeInfo.reason;
            Logger::log(LogLevel::Info, "ws closed: " + close_reason);
        } });

  socket.start();

  // Wait for connection or timeout
  auto timeout_start = std::chrono::steady_clock::now();
  while (!connection_opened.load(std::memory_order_acquire) &&
         !connection_error.load(std::memory_order_acquire) &&
         !shutdown_requested_.load(std::memory_order_acquire))
  {

    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                       std::chrono::steady_clock::now() - timeout_start)
                       .count();

    if (static_cast<std::uint32_t>(elapsed) >= config_.connection_timeout_ms)
    {
      Logger::log(LogLevel::Warn, "connection timeout after " +
                                      std::to_string(config_.connection_timeout_ms) + "ms");
      socket.stop();
      set_state(ConnectionState::Disconnected, "connection timeout");
      return false;
    }

    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }

  if (connection_error.load(std::memory_order_acquire) ||
      !connection_opened.load(std::memory_order_acquire))
  {
    socket.stop();
    set_state(ConnectionState::Disconnected, close_reason.empty() ? "connection failed" : close_reason);
    return false;
  }

  // Connection established - run until closed or shutdown
  while (!connection_closed.load(std::memory_order_acquire) &&
         !connection_error.load(std::memory_order_acquire) &&
         !shutdown_requested_.load(std::memory_order_acquire))
  {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }

  socket.stop();

  if (shutdown_requested_.load(std::memory_order_acquire))
  {
    set_state(ConnectionState::Shutdown, "shutdown requested");
    return true;
  }

  set_state(ConnectionState::Disconnected, close_reason.empty() ? "connection lost" : close_reason);
  return connection_opened.load(std::memory_order_acquire); // Return true if we were connected
}

// Legacy method - single connection attempt for backward compatibility
void WsClient::connect_and_run()
{
  ix::initNetSystem();
  ix::WebSocket socket;
  socket.setUrl(config_.endpoint);

  socket.setOnMessageCallback([&](const ix::WebSocketMessagePtr &msg)
                              {
        if (msg->type == ix::WebSocketMessageType::Open) {
            Logger::log(LogLevel::Info, "connected, sending AUTH");
            socket.sendText(initial_message_);
        } else if (msg->type == ix::WebSocketMessageType::Message) {
            Logger::log(LogLevel::Debug, std::string("received: ") + msg->str);
            try {
                auto parsed = nlohmann::json::parse(msg->str);
                std::string mtype = parsed.value("type", "");
                if (mtype == "AUTH_ACK") {
                    std::string session_id = parsed["body"].value("session_id", "");
                    if (!session_id.empty()) {
                        last_session_id_ = session_id;
                        state_impl_.set_session_id(session_id);
                        if (!heartbeat_sent_) {
                            auto hb = build_signed_heartbeat_json(config_.device_id, session_id, "alive", 120, "ok");
                            socket.sendText(hb);
                            heartbeat_sent_ = true;
                        }
                        if (!telemetry_sent_) {
                            auto tel = build_signed_telemetry_json(config_.device_id, session_id);
                            socket.sendText(tel);
                            telemetry_sent_ = true;
                        }
                    }
                } else if (mtype == "POLICY_UPDATE") {
                    auto body = parsed["body"];
                    std::string policy_hash = body.value("policy_hash", "");
                    state_impl_.set_policy_hash(policy_hash);
                    Logger::log(LogLevel::Info, "policy updated: " + policy_hash);
                } else if (mtype == "COMMAND_DELIVERY") {
                    std::string session_id = parsed.value("session_id", "");
                    auto body = parsed["body"];
                    auto envelope = body["command_envelope"];
                    std::string command_message_id = envelope.value("message_id", "");
                    std::string trace_id = envelope.value("trace_id", "");
                    std::string method = envelope["body"].value("method", "");
                    std::string policy_hash = envelope["meta"].value("policy_hash", "");

                    if (!session_id.empty() && !command_message_id.empty()) {
                        // Verify command envelope signature before processing
                        if (is_signature_verification_required()) {
                            std::string envelope_str = envelope.dump();
                            auto verify_result = crypto::verify_command_envelope(envelope_str, last_command_seq_, "");
                            
                            if (!verify_result.valid) {
                                Logger::log(LogLevel::Warn, "COMMAND_DELIVERY signature verification failed: " + 
                                           verify_result.error_code + " - " + verify_result.error_message);
                                
                                // Send rejection ACK with reason
                                auto rejected_ack = build_command_ack_json(config_.device_id, session_id, command_message_id, 
                                                                           "rejected", verify_result.error_code);
                                socket.sendText(rejected_ack);
                                
                                // Send error result
                                int error_code = 4003;
                                if (verify_result.error_code == "TTL_EXPIRED") error_code = 4005;
                                else if (verify_result.error_code == "SEQ_REPLAY") error_code = 4006;
                                
                                auto denied = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                        trace_id, "failed", verify_result.error_code,
                                                                        verify_result.error_message, "", "", error_code, "");
                                socket.sendText(denied);
                                return;
                            }
                            
                            // Update last sequence on successful verification
                            std::uint64_t new_seq = envelope.value("seq", static_cast<std::uint64_t>(0));
                            if (new_seq > last_command_seq_) {
                                last_command_seq_ = new_seq;
                            }
                            
                            Logger::log(LogLevel::Debug, "COMMAND_DELIVERY signature verified successfully");
                        }
                        
                        auto ack = build_command_ack_json(config_.device_id, session_id, command_message_id, "received", "");
                        socket.sendText(ack);

                        if (quarantine_.is_quarantined() && !quarantine_.is_allowed(method)) {
                            auto denied = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                    trace_id, "failed", "denied",
                                                                    "quarantined", "", "", 4001,
                                                                    quarantine_.reason());
                            socket.sendText(denied);
                            return;
                        }

                        if (!policy_hash.empty() && !state_impl_.policy_hash().empty() && policy_hash != state_impl_.policy_hash()) {
                            auto denied = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                    trace_id, "failed", "policy_mismatch",
                                                                    "policy hash mismatch", "", "", 4002, "");
                            socket.sendText(denied);
                            return;
                        }

                        IoctlClient ioctl;
                        if (method == "lock_screen") {
                            auto res = ioctl.lock_screen(command_message_id, state_impl_, command_message_id);
                            auto result_msg = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                        trace_id, "completed", "ok", "lock_screen done",
                                                                        "", "", res.error_code, res.error_message);
                            socket.sendText(result_msg);
                        } else if (method == "ping") {
                            auto res = ioctl.ping(command_message_id, state_impl_, command_message_id);
                            auto result_msg = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                        trace_id, "completed", "ok", res.result,
                                                                        "", "", res.error_code, res.error_message);
                            socket.sendText(result_msg);
                        } else {
                            auto not_supported = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                           trace_id, "failed", "unsupported",
                                                                           "command not supported", "", "", 4004, "");
                            socket.sendText(not_supported);
                        }
                    }
                } else if (mtype == "UPDATE_ANNOUNCE") {
                    std::string session_id = parsed.value("session_id", "");
                    auto body = parsed["body"];
                    std::string release_id = body.value("release_id", "");
                    std::string version = body.value("version", "");
                    if (!session_id.empty() && !release_id.empty()) {
                        std::unordered_map<std::string, std::string> manifest;
                        manifest["release_id"] = release_id;
                        manifest["version"] = version;
                        ota_.set_manifest(manifest);
                        state_impl_.set_release(release_id);
                        auto status_msg = build_update_status_json(
                            config_.device_id, session_id, release_id, "precheck", version, 0, "acknowledged", 0, "", "");
                        socket.sendText(status_msg);
                    }
                }
            } catch (const std::exception& e) {
                Logger::log(LogLevel::Error, std::string("parse error: ") + e.what());
            }
        } else if (msg->type == ix::WebSocketMessageType::Error) {
            Logger::log(LogLevel::Error, std::string("ws error: ") + msg->errorInfo.reason);
        } else if (msg->type == ix::WebSocketMessageType::Close) {
            Logger::log(LogLevel::Info, "ws closed");
        } });

  socket.start();

  std::this_thread::sleep_for(std::chrono::seconds(5));

  socket.stop();
}
