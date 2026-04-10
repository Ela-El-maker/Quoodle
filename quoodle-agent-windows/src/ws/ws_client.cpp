#include "ws_client.hpp"

#include <chrono>
#include <cstdio>
#include <iostream>
#include <thread>
#include <unordered_map>
#include <algorithm>
#include <cstdlib>
#include <mutex>

#include <ixwebsocket/IXNetSystem.h>
#include <ixwebsocket/IXWebSocket.h>
#include <nlohmann/json.hpp>

#include "../kernel/kernel_event_listener.hpp"
#include "../crypto/command_verifier.hpp"
#include "../command/dispatcher.hpp"
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

static bool is_kernel_driver_enabled()
{
  const char *env = std::getenv("QUOODLE_USE_KERNEL_DRIVER");
  return env && std::string(env) != "0";
}

static std::string trim_trailing_slash(const std::string &url)
{
  if (url.empty())
  {
    return url;
  }
  std::string out = url;
  while (!out.empty() && out.back() == '/')
  {
    out.pop_back();
  }
  return out;
}

static std::string now_iso_utc()
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

static bool parse_ws_telemetry_to_http_payload(
    const std::string &ws_envelope_json,
    std::string &http_payload_json,
    std::int64_t &seq_out)
{
  try
  {
    const auto envelope = nlohmann::json::parse(ws_envelope_json);
    const auto &body = envelope.at("body");

    nlohmann::json payload;
    payload["schema_version"] = body.value("schema_version", "v1");
    payload["device_id"] = envelope.value("device_id", "");
    payload["session_id"] = envelope.value("session_id", body.value("session_id", ""));
    payload["timestamp"] = body.value("timestamp", envelope.value("timestamp", ""));
    payload["seq"] = envelope.value("seq", body.value("seq", 0));
    payload["telemetry_scope"] = body.value("telemetry_scope", "telemetry_extended");
    payload["metrics"] = body.value("metrics", nlohmann::json::object());
    if (body.contains("policy_hash"))
    {
      payload["policy_hash"] = body["policy_hash"];
    }
    if (body.contains("machine_secret_hash"))
    {
      payload["machine_secret_hash"] = body["machine_secret_hash"];
    }
    payload["masked_fields"] = body.value("masked_fields", nlohmann::json::array());

    seq_out = payload["seq"].is_number_integer() ? payload["seq"].get<std::int64_t>() : 0;
    http_payload_json = payload.dump();
    return true;
  }
  catch (const std::exception &)
  {
    return false;
  }
}

WsClient::WsClient(const AgentConfig &config)
    : config_(config),
      state_impl_(config.device_id),
      telemetry_queue_(TelemetryQueueConfig{
          config.telemetry_queue_db_path,
          static_cast<std::int32_t>(config.telemetry_max_queue_items),
          5000,
          true}),
      current_delay_ms_(config.reconnection.initial_delay_ms),
      rng_(std::random_device{}())
{
  if (!telemetry_queue_.open())
  {
    Logger::log(LogLevel::Warn, "telemetry queue unavailable; fallback buffering disabled");
  }
}

WsClient::WsClient(std::string endpoint, std::string device_id)
    : state_impl_(device_id),
      telemetry_queue_(TelemetryQueueConfig{}),
      rng_(std::random_device{}())
{
  config_.endpoint = std::move(endpoint);
  config_.device_id = std::move(device_id);
  current_delay_ms_ = config_.reconnection.initial_delay_ms;
  if (!telemetry_queue_.open())
  {
    Logger::log(LogLevel::Warn, "telemetry queue unavailable; fallback buffering disabled");
  }
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

bool WsClient::send_telemetry_http(const std::string &endpoint_path,
                                   const std::string &payload_json,
                                   std::string &error_reason,
                                   std::string *response_body,
                                   int *status_code)
{
  if (!config_.telemetry_http_fallback || config_.jwt.empty())
  {
    error_reason = "http_fallback_disabled";
    return false;
  }

  const std::string base = trim_trailing_slash(config_.telemetry_fallback_url);
  if (base.empty())
  {
    error_reason = "fallback_url_missing";
    return false;
  }

  const auto response = telemetry_http_client_.post_json(base + endpoint_path, config_.jwt, payload_json, config_.connection_timeout_ms);
  if (response_body)
  {
    *response_body = response.body;
  }
  if (status_code)
  {
    *status_code = response.status_code;
  }
  if (!response.ok)
  {
    error_reason = response.error_reason.empty() ? ("http_" + std::to_string(response.status_code)) : response.error_reason;
    return false;
  }

  telemetry_stats_.last_success_ts = now_iso_utc();
  return true;
}

void WsClient::queue_telemetry_payload(const std::string &payload_json, std::int64_t seq, const std::string &reason)
{
  if (!telemetry_queue_.is_open())
  {
    telemetry_stats_.dropped += 1;
    Logger::log(LogLevel::Warn, "telemetry dropped (queue unavailable): " + reason);
    return;
  }
  const std::int32_t dropped_now = telemetry_queue_.enqueue(seq, payload_json, reason);
  telemetry_stats_.queued += 1;
  if (dropped_now > 0)
  {
    telemetry_stats_.dropped += static_cast<std::uint64_t>(dropped_now);
    Logger::log(LogLevel::Warn, "telemetry queue drop policy triggered (dropped=" + std::to_string(dropped_now) + ")");
  }
}

bool WsClient::replay_queued_telemetry()
{
  if (!telemetry_queue_.is_open() || !config_.telemetry_http_fallback)
  {
    return false;
  }

  const auto pending = telemetry_queue_.fetch_batch(static_cast<std::int32_t>(config_.telemetry_batch_size),
                                                    static_cast<std::int64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                                                                 std::chrono::system_clock::now().time_since_epoch())
                                                                                 .count()));
  if (pending.empty())
  {
    return false;
  }

  nlohmann::json batch = nlohmann::json::object();
  nlohmann::json entries = nlohmann::json::array();
  std::string device_id = config_.device_id;

  for (const auto &item : pending)
  {
    try
    {
      const auto payload = nlohmann::json::parse(item.payload_json);
      if (payload.contains("device_id") && payload["device_id"].is_string())
      {
        device_id = payload["device_id"].get<std::string>();
      }
      entries.push_back(payload);
    }
    catch (const std::exception &)
    {
      telemetry_queue_.mark_failed(item.id, "invalid_queue_payload", static_cast<std::int64_t>(
                                                                   std::chrono::duration_cast<std::chrono::milliseconds>(
                                                                       std::chrono::system_clock::now().time_since_epoch())
                                                                       .count() +
                                                                   config_.telemetry_retry_backoff_s * 1000ULL));
      telemetry_stats_.retry_count += 1;
    }
  }
  if (entries.empty())
  {
    return false;
  }

  batch["device_id"] = device_id;
  batch["entries"] = entries;

  std::string error;
  std::string response_body;
  if (send_telemetry_http("/api/v1/telemetry/batch", batch.dump(), error, &response_body, nullptr))
  {
    std::vector<std::int64_t> success_ids;
    success_ids.reserve(pending.size());

    // Default to full success if response body is absent/unparseable.
    bool parsed_response = false;
    try
    {
      const auto parsed = nlohmann::json::parse(response_body);
      const std::string status = parsed.value("status", "accepted");
      if (status == "accepted")
      {
        parsed_response = true;
        for (const auto &item : pending)
        {
          success_ids.push_back(item.id);
        }
      }
      else if (status == "partial_accept")
      {
        parsed_response = true;
        std::unordered_map<int, std::string> rejected_indexes;
        const auto errors = parsed.value("errors", nlohmann::json::array());
        for (const auto &entry : errors)
        {
          if (entry.is_object() && entry.contains("index"))
          {
            const int idx = entry.value("index", -1);
            rejected_indexes[idx] = entry.value("reason", "partial_reject");
          }
        }

        const auto now_ms = static_cast<std::int64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                                           std::chrono::system_clock::now().time_since_epoch())
                                                           .count());

        for (std::size_t i = 0; i < pending.size(); ++i)
        {
          auto it = rejected_indexes.find(static_cast<int>(i));
          if (it == rejected_indexes.end())
          {
            success_ids.push_back(pending[i].id);
            continue;
          }
          const std::uint64_t backoff_s = std::min<std::uint64_t>(
              static_cast<std::uint64_t>(config_.telemetry_retry_backoff_s) * (1ULL << std::min(pending[i].retry_count, 6)),
              static_cast<std::uint64_t>(config_.telemetry_retry_backoff_max_s));
          telemetry_queue_.mark_failed(pending[i].id, it->second, now_ms + static_cast<std::int64_t>(backoff_s * 1000ULL));
          telemetry_stats_.retry_count += 1;
        }
      }
      else if (status == "rejected")
      {
        parsed_response = true;
        const auto now_ms = static_cast<std::int64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                                           std::chrono::system_clock::now().time_since_epoch())
                                                           .count());
        for (const auto &item : pending)
        {
          const std::uint64_t backoff_s = std::min<std::uint64_t>(
              static_cast<std::uint64_t>(config_.telemetry_retry_backoff_s) * (1ULL << std::min(item.retry_count, 6)),
              static_cast<std::uint64_t>(config_.telemetry_retry_backoff_max_s));
          telemetry_queue_.mark_failed(item.id, "batch_rejected", now_ms + static_cast<std::int64_t>(backoff_s * 1000ULL));
          telemetry_stats_.retry_count += 1;
        }
      }
    }
    catch (const std::exception &)
    {
      parsed_response = false;
    }

    if (!parsed_response)
    {
      for (const auto &item : pending)
      {
        success_ids.push_back(item.id);
      }
    }

    if (!success_ids.empty() && telemetry_queue_.delete_ids(success_ids))
    {
      telemetry_stats_.replayed += static_cast<std::uint64_t>(success_ids.size());
      Logger::log(LogLevel::Info, "telemetry replayed via HTTP batch: " + std::to_string(success_ids.size()));
      return true;
    }
    return !success_ids.empty();
  }

  const auto now_ms = static_cast<std::int64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                                     std::chrono::system_clock::now().time_since_epoch())
                                                     .count());
  for (const auto &item : pending)
  {
    const std::uint64_t backoff_s = std::min<std::uint64_t>(
        static_cast<std::uint64_t>(config_.telemetry_retry_backoff_s) * (1ULL << std::min(item.retry_count, 6)),
        static_cast<std::uint64_t>(config_.telemetry_retry_backoff_max_s));
    telemetry_queue_.mark_failed(item.id, error, now_ms + static_cast<std::int64_t>(backoff_s * 1000ULL));
    telemetry_stats_.retry_count += 1;
  }
  Logger::log(LogLevel::Warn, "telemetry replay failed: " + error);
  return false;
}

void WsClient::run_disconnected_telemetry_tick(bool extended_scope)
{
  const std::string session_for_http = last_session_id_.empty() ? "offline" : last_session_id_;
  const char *scope = extended_scope ? "telemetry_extended" : "telemetry_basic";
  auto telemetry_ws = build_signed_telemetry_json(config_.device_id, session_for_http, scope, state_impl_.policy_hash());
  std::string payload;
  std::int64_t seq = 0;
  if (!telemetry_ws.empty() && parse_ws_telemetry_to_http_payload(telemetry_ws, payload, seq))
  {
    std::string reason;
    if (send_telemetry_http("/api/v1/telemetry/heartbeat", payload, reason))
    {
      telemetry_stats_.sent += 1;
    }
    else
    {
      queue_telemetry_payload(payload, seq, reason);
    }
  }

  replay_queued_telemetry();
}

void WsClient::run()
{
  ix::initNetSystem();

  Logger::log(LogLevel::Info, "starting WebSocket client with reconnection support");
  Logger::log(LogLevel::Debug, "reconnection config: initial_delay=" +
                                   std::to_string(config_.reconnection.initial_delay_ms) + "ms, max_delay=" +
                                   std::to_string(config_.reconnection.max_delay_ms) + "ms, multiplier=" +
                                   std::to_string(config_.reconnection.backoff_multiplier));

  auto next_disconnected_heartbeat = std::chrono::steady_clock::now() + std::chrono::seconds(config_.heartbeat_interval_s);
  auto next_disconnected_telemetry = std::chrono::steady_clock::now() + std::chrono::seconds(config_.telemetry_interval_s);

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
      const auto now = std::chrono::steady_clock::now();
      if (now >= next_disconnected_heartbeat)
      {
        run_disconnected_telemetry_tick(false);
        next_disconnected_heartbeat = now + std::chrono::seconds(config_.heartbeat_interval_s);
      }
      if (now >= next_disconnected_telemetry)
      {
        run_disconnected_telemetry_tick(true);
        next_disconnected_telemetry = now + std::chrono::seconds(config_.telemetry_interval_s);
      }
      if (now - last_metrics_log_ >= std::chrono::seconds(60))
      {
        last_metrics_log_ = now;
        Logger::log(
            LogLevel::Info,
            "telemetry stats: sent=" + std::to_string(telemetry_stats_.sent) +
                " queued=" + std::to_string(telemetry_stats_.queued) +
                " replayed=" + std::to_string(telemetry_stats_.replayed) +
                " dropped=" + std::to_string(telemetry_stats_.dropped) +
                " retries=" + std::to_string(telemetry_stats_.retry_count) +
                (telemetry_stats_.last_success_ts.empty() ? "" : (" last_success=" + telemetry_stats_.last_success_ts)));
      }

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
  std::atomic<bool> authenticated{false};
  std::mutex session_mutex;
  std::string active_session_id;
  std::string close_reason;
  auto last_heartbeat_tick = std::chrono::steady_clock::now();
  auto last_telemetry_tick = std::chrono::steady_clock::now();
  auto last_replay_tick = std::chrono::steady_clock::now();

  // Reset per-connection state
  heartbeat_sent_ = false;
  telemetry_sent_ = false;

  KernelEventListener kernel_listener;
  std::atomic<bool> kernel_listener_started{false};

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
            std::string auth_message;
            if (!config_.jwt.empty()) {
                auto envelope = build_auth_envelope(config_.device_id, config_.jwt);
                auth_message = build_signed_auth_json(std::move(envelope));
                if (auth_message.empty()) {
                    close_reason = "failed to build AUTH payload";
                    connection_error.store(true, std::memory_order_release);
                    Logger::log(LogLevel::Error, close_reason);
                    return;
                }
            } else if (!initial_message_.empty()) {
                // Legacy fallback for older call sites that pre-build AUTH once.
                Logger::log(LogLevel::Warn, "AGENT_JWT not set; reusing legacy initial AUTH payload");
                auth_message = initial_message_;
            } else {
                close_reason = "missing AGENT_JWT and initial AUTH payload";
                connection_error.store(true, std::memory_order_release);
                Logger::log(LogLevel::Error, close_reason);
                return;
            }

            socket.sendText(auth_message);
            
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
                        {
                            std::lock_guard<std::mutex> guard(session_mutex);
                            active_session_id = session_id;
                        }
                        authenticated.store(true, std::memory_order_release);
                        const std::string ack_policy_hash = parsed["body"].value("policy_hash", "");
                        if (!ack_policy_hash.empty()) {
                            state_impl_.set_policy_hash(ack_policy_hash);
                        }
                        if (!heartbeat_sent_) {
                            auto hb = build_signed_heartbeat_json(config_.device_id, session_id, "alive", 120, "ok");
                            socket.sendText(hb);
                            heartbeat_sent_ = true;
                            telemetry_stats_.sent += 1;
                        }
                        if (!telemetry_sent_) {
                            auto tel = build_signed_telemetry_json(
                                config_.device_id,
                                session_id,
                                "telemetry_extended",
                                state_impl_.policy_hash());
                            socket.sendText(tel);
                            telemetry_sent_ = true;
                            telemetry_stats_.sent += 1;
                            replay_queued_telemetry();
                        }
                        if (is_kernel_driver_enabled() && !kernel_listener_started.load()) {
                            const std::string session_id_copy = session_id;
                            bool started = kernel_listener.start([&, session_id_copy](const KernelEvent &evt) {
                                auto tel = build_signed_kernel_event_telemetry_json(
                                    config_.device_id,
                                    session_id_copy,
                                    evt.event_id,
                                    evt.event_type,
                                    evt.timestamp_unix,
                                    evt.payload_json);
                                if (!tel.empty()) {
                                    socket.sendText(tel);
                                }
                            });
                            if (started) {
                                kernel_listener_started.store(true);
                                Logger::log(LogLevel::Info, "kernel event listener started");
                            }
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

                        nlohmann::json params_obj = envelope["body"].value("params", nlohmann::json::object());
                        CommandDispatcher dispatcher;
                        auto res = dispatcher.dispatch(
                            method,
                            command_message_id,
                            state_impl_,
                            params_obj.dump(),
                            command_message_id);

                        if (res.status == "ok") {
                            auto result_payload = res.result.empty() ? "command completed" : res.result;
                            auto result_msg = build_command_result_json(
                                config_.device_id, session_id, command_message_id, trace_id,
                                "completed", "ok", result_payload, "", "",
                                res.error_code, res.error_message);
                            socket.sendText(result_msg);
                        } else {
                            const bool unsupported = (res.status == "invalid_opcode" || res.error_code == 4004 || res.error_code == 4002);
                            auto result_msg = build_command_result_json(
                                config_.device_id, session_id, command_message_id, trace_id,
                                "failed",
                                unsupported ? "unsupported" : "kernel_transport_error",
                                res.error_message.empty() ? "command execution failed" : res.error_message,
                                "", "",
                                res.error_code,
                                res.error_message);
                            socket.sendText(result_msg);
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
    const auto now = std::chrono::steady_clock::now();
    if (authenticated.load(std::memory_order_acquire))
    {
      std::string session_id;
      {
        std::lock_guard<std::mutex> guard(session_mutex);
        session_id = active_session_id;
      }

      if (!session_id.empty())
      {
        if (now - last_heartbeat_tick >= std::chrono::seconds(config_.heartbeat_interval_s))
        {
          const auto hb = build_signed_heartbeat_json(config_.device_id, session_id, "alive", 120, "ok");
          if (!hb.empty())
          {
            socket.sendText(hb);
            telemetry_stats_.sent += 1;
          }
          last_heartbeat_tick = now;
        }

        if (now - last_telemetry_tick >= std::chrono::seconds(config_.telemetry_interval_s))
        {
          const auto telemetry = build_signed_telemetry_json(
              config_.device_id,
              session_id,
              "telemetry_extended",
              state_impl_.policy_hash());
          if (!telemetry.empty())
          {
            socket.sendText(telemetry);
            telemetry_stats_.sent += 1;
          }
          last_telemetry_tick = now;
        }

        if (now - last_replay_tick >= std::chrono::seconds(5))
        {
          replay_queued_telemetry();
          last_replay_tick = now;
        }
      }
    }

    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }

  socket.stop();
  kernel_listener.stop();

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
  shutdown_requested_.store(false, std::memory_order_release);
  reconnect_attempts_.store(0, std::memory_order_release);
  current_delay_ms_ = config_.reconnection.initial_delay_ms;
  (void)try_connect();
}
