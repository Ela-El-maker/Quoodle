#include "ws_client.hpp"

#include <chrono>
#include <cstdio>
#include <iostream>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <algorithm>
#include <cstdlib>
#include <ctime>
#include <mutex>
#include <sstream>

#include <ixwebsocket/IXNetSystem.h>
#include <ixwebsocket/IXWebSocket.h>
#include <nlohmann/json.hpp>

#include "../kernel/kernel_event_listener.hpp"
#include "../crypto/command_verifier.hpp"
#include "../command/dispatcher.hpp"
#include "../command/lock_screen_command.hpp"
#include "../command/observability_command.hpp"
#include "../command/screenshot_command.hpp"
#include "../kernel/ioctl_client.hpp"
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

static bool starts_with(const std::string &value, const char *prefix)
{
  return value.rfind(prefix, 0) == 0;
}

static std::string to_lower_copy(std::string value)
{
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch)
                 { return static_cast<char>(std::tolower(ch)); });
  return value;
}

static bool is_kernel_reason(const std::string &reason)
{
  return starts_with(reason, "kernel_");
}

static bool is_kernel_http_payload(const std::string &payload_json)
{
  try
  {
    const auto payload = nlohmann::json::parse(payload_json);
    return payload.value("telemetry_scope", "") == "kernel_event";
  }
  catch (const std::exception &)
  {
    return false;
  }
}

struct ParsedCommandOutput
{
  std::string notes;
  std::string output_text;
  std::string data_json;
};

static ParsedCommandOutput parse_command_output_payload(const std::string &raw_result)
{
  ParsedCommandOutput parsed{};
  if (raw_result.empty())
  {
    parsed.notes = "command completed";
    return parsed;
  }

  parsed.notes = raw_result;
  try
  {
    const auto value = nlohmann::json::parse(raw_result);
    if (value.is_object() || value.is_array())
    {
      parsed.notes = "structured result";
      parsed.data_json = value.dump();
      return parsed;
    }

    if (value.is_string())
    {
      parsed.output_text = value.get<std::string>();
      parsed.notes = parsed.output_text;
      return parsed;
    }

    parsed.output_text = value.dump();
    parsed.notes = parsed.output_text;
    return parsed;
  }
  catch (const std::exception &)
  {
    parsed.output_text = raw_result;
    parsed.notes = raw_result;
    return parsed;
  }
}

static std::string sanitize_app_lock_scalar(std::string value)
{
  std::replace(value.begin(), value.end(), '\r', ' ');
  std::replace(value.begin(), value.end(), '\n', ' ');
  std::replace(value.begin(), value.end(), '=', ':');
  return value;
}

static bool try_parse_unix_seconds(const nlohmann::json &value, std::uint64_t &out_seconds)
{
  if (value.is_number_unsigned())
  {
    out_seconds = value.get<std::uint64_t>();
    return true;
  }
  if (value.is_number_integer())
  {
    const auto parsed = value.get<std::int64_t>();
    if (parsed > 0)
    {
      out_seconds = static_cast<std::uint64_t>(parsed);
      return true;
    }
    return false;
  }
  if (value.is_string())
  {
    const auto text = value.get<std::string>();
    if (text.empty())
    {
      return false;
    }
    bool digits_only = std::all_of(text.begin(), text.end(), [](unsigned char ch)
                                   { return ch >= '0' && ch <= '9'; });
    if (!digits_only)
    {
      return false;
    }
    try
    {
      out_seconds = std::stoull(text);
      return out_seconds > 0;
    }
    catch (const std::exception &)
    {
      return false;
    }
  }
  return false;
}

static bool build_app_lock_policy_blob(const nlohmann::json &app_lock,
                                       const std::string &default_policy_hash,
                                       std::string &blob_out,
                                       std::string &error_out)
{
  if (!app_lock.is_object())
  {
    error_out = "app_lock_not_object";
    return false;
  }

  const bool enabled = app_lock.value("enabled", false);
  const std::string mode = sanitize_app_lock_scalar(app_lock.value("mode", std::string("blocklist")));
  const std::string fail_mode = sanitize_app_lock_scalar(app_lock.value("fail_mode", std::string("open")));
  const std::string policy_version = sanitize_app_lock_scalar(app_lock.value("policy_version", std::string()));
  const std::string policy_hash = sanitize_app_lock_scalar(app_lock.value("policy_hash", default_policy_hash));
  std::uint32_t event_dedupe_sec = 30;
  if (app_lock.contains("event_dedupe_sec") && app_lock["event_dedupe_sec"].is_number_integer())
  {
    const auto parsed = app_lock["event_dedupe_sec"].get<std::int64_t>();
    if (parsed > 0)
    {
      event_dedupe_sec = static_cast<std::uint32_t>(std::min<std::int64_t>(parsed, 3600));
    }
  }

  if (mode != "blocklist")
  {
    error_out = "unsupported_mode";
    return false;
  }

  if (fail_mode != "open")
  {
    error_out = "unsupported_fail_mode";
    return false;
  }

  std::ostringstream lines;
  lines << "enabled=" << (enabled ? "1" : "0") << "\n";
  lines << "mode=" << mode << "\n";
  lines << "fail_mode=" << fail_mode << "\n";
  lines << "policy_version=" << policy_version << "\n";
  lines << "policy_hash=" << policy_hash << "\n";
  lines << "event_dedupe_sec=" << event_dedupe_sec << "\n";

  std::size_t rule_index = 0;
  if (app_lock.contains("rules") && app_lock["rules"].is_array())
  {
    for (const auto &rule : app_lock["rules"])
    {
      if (!rule.is_object())
      {
        continue;
      }

      const std::string action = to_lower_copy(rule.value("action", std::string("block")));
      if (action != "block")
      {
        continue;
      }

      const std::string match_type = to_lower_copy(rule.value("match_type", std::string()));
      if (match_type != "basename" && match_type != "full_path")
      {
        continue;
      }

      const std::string value = sanitize_app_lock_scalar(rule.value("value", std::string()));
      if (value.empty())
      {
        continue;
      }

      std::string rule_id = sanitize_app_lock_scalar(rule.value("rule_id", std::string()));
      if (rule_id.empty())
      {
        rule_id = "rule-" + std::to_string(rule_index);
      }

      std::uint32_t priority = 1000;
      if (rule.contains("priority") && rule["priority"].is_number_integer())
      {
        const auto parsed = rule["priority"].get<std::int64_t>();
        if (parsed > 0 && parsed < 1000000)
        {
          priority = static_cast<std::uint32_t>(parsed);
        }
      }

      lines << "rule." << rule_index << ".rule_id=" << rule_id << "\n";
      lines << "rule." << rule_index << ".match_type=" << match_type << "\n";
      lines << "rule." << rule_index << ".value=" << value << "\n";
      lines << "rule." << rule_index << ".priority=" << priority << "\n";

      if (rule.contains("expires_at") && !rule["expires_at"].is_null())
      {
        std::uint64_t expires_at_unix = 0;
        if (try_parse_unix_seconds(rule["expires_at"], expires_at_unix) && expires_at_unix > 0)
        {
          lines << "rule." << rule_index << ".expires_at=" << expires_at_unix << "\n";
        }
      }

      rule_index++;
      if (rule_index >= 64)
      {
        break;
      }
    }
  }

  blob_out = lines.str();
  if (blob_out.empty())
  {
    error_out = "empty_policy_blob";
    return false;
  }
  if (blob_out.size() >= QUOODLE_MAX_PARAMS)
  {
    error_out = "policy_blob_too_large";
    return false;
  }

  return true;
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
  if (suspend_http_fallback_.load(std::memory_order_acquire))
  {
    error_reason = "fallback_suspended_auth";
    return false;
  }

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
    if (response.status_code == 401)
    {
      suspend_http_fallback_.store(true, std::memory_order_release);
      error_reason = "http_unauthorized";
      return false;
    }
    error_reason = response.error_reason.empty() ? ("http_" + std::to_string(response.status_code)) : response.error_reason;
    return false;
  }

  telemetry_stats_.last_success_ts = now_iso_utc();
  return true;
}

void WsClient::queue_telemetry_payload(const std::string &payload_json, std::int64_t seq, const std::string &reason)
{
  const bool kernel_payload = is_kernel_reason(reason) || is_kernel_http_payload(payload_json);
  if (!telemetry_queue_.is_open())
  {
    telemetry_stats_.dropped += 1;
    if (kernel_payload)
    {
      telemetry_stats_.kernel_dropped += 1;
    }
    Logger::log(LogLevel::Warn, "telemetry dropped (queue unavailable): " + reason);
    return;
  }
  const std::int32_t dropped_now = telemetry_queue_.enqueue(seq, payload_json, reason);
  telemetry_stats_.queued += 1;
  if (kernel_payload)
  {
    telemetry_stats_.kernel_queued += 1;
  }
  if (dropped_now > 0)
  {
    telemetry_stats_.dropped += static_cast<std::uint64_t>(dropped_now);
    if (kernel_payload)
    {
      telemetry_stats_.kernel_dropped += static_cast<std::uint64_t>(dropped_now);
    }
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
  std::unordered_map<std::int64_t, bool> pending_is_kernel;

  for (const auto &item : pending)
  {
    try
    {
      const auto payload = nlohmann::json::parse(item.payload_json);
      pending_is_kernel[item.id] = payload.value("telemetry_scope", "") == "kernel_event";
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
      if (pending_is_kernel[item.id])
      {
        telemetry_stats_.kernel_retry += 1;
      }
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
          if (pending_is_kernel[pending[i].id])
          {
            telemetry_stats_.kernel_retry += 1;
          }
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
          if (pending_is_kernel[item.id])
          {
            telemetry_stats_.kernel_retry += 1;
          }
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
      std::uint64_t kernel_replayed = 0;
      for (const auto id : success_ids)
      {
        if (pending_is_kernel[id])
        {
          kernel_replayed += 1;
        }
      }
      telemetry_stats_.replayed += static_cast<std::uint64_t>(success_ids.size());
      telemetry_stats_.kernel_replayed += kernel_replayed;
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
    if (pending_is_kernel[item.id])
    {
      telemetry_stats_.kernel_retry += 1;
    }
  }
  Logger::log(LogLevel::Warn, "telemetry replay failed: " + error);
  return false;
}

bool WsClient::kernel_category_enabled(const std::string &category) const
{
  const std::string normalized = to_lower_copy(category);
  if (normalized == "exec")
  {
    return config_.kernel_enable_exec;
  }
  if (normalized == "integrity")
  {
    return config_.kernel_enable_integrity;
  }
  if (normalized == "attestation")
  {
    return config_.kernel_enable_attestation;
  }
  if (normalized == "update")
  {
    return config_.kernel_enable_update;
  }
  if (normalized == "runtime")
  {
    return config_.kernel_enable_runtime;
  }
  return false;
}

bool WsClient::kernel_category_sampled(const std::string &category)
{
  const std::string normalized = to_lower_copy(category);
  std::uint32_t threshold = 100;
  if (normalized == "exec")
    threshold = config_.kernel_sample_exec_pct;
  else if (normalized == "integrity")
    threshold = config_.kernel_sample_integrity_pct;
  else if (normalized == "attestation")
    threshold = config_.kernel_sample_attestation_pct;
  else if (normalized == "update")
    threshold = config_.kernel_sample_update_pct;
  else if (normalized == "runtime")
    threshold = config_.kernel_sample_runtime_pct;

  if (threshold >= 100)
  {
    return true;
  }
  if (threshold == 0)
  {
    return false;
  }
  std::uniform_int_distribution<int> dist(1, 100);
  return static_cast<std::uint32_t>(dist(rng_)) <= threshold;
}

std::string WsClient::normalize_kernel_payload_json(const std::string &payload_json, std::string &category_out, bool &masked)
{
  masked = false;
  category_out = "exec";
  try
  {
    auto parsed = nlohmann::json::parse(payload_json);
    if (!parsed.is_object())
    {
      return payload_json;
    }

    const std::unordered_set<std::string> allowed_categories = {
        "exec", "integrity", "attestation", "update", "runtime"};
    std::string category = to_lower_copy(parsed.value("category", std::string("exec")));
    if (allowed_categories.find(category) == allowed_categories.end())
    {
      category = "exec";
    }
    category_out = category;

    parsed["category"] = category;
    if (!parsed.contains("subtype"))
      parsed["subtype"] = "opcode";
    if (!parsed.contains("severity"))
    {
      const bool has_error = parsed.value("error_code", 0) != 0 || to_lower_copy(parsed.value("status", std::string("ok"))) != "ok";
      parsed["severity"] = has_error ? "high" : "info";
    }
    if (!parsed.contains("decision"))
    {
      const std::string status = to_lower_copy(parsed.value("status", std::string("ok")));
      parsed["decision"] = (status == "ok" || status == "completed") ? "allow" : "deny";
    }
    if (!parsed.contains("reason_code"))
    {
      parsed["reason_code"] = to_lower_copy(parsed.value("status", std::string("ok")));
    }

    if (!parsed.contains("duration_ms"))
      parsed["duration_ms"] = 0;
    if (!parsed.contains("queue_depth"))
      parsed["queue_depth"] = 0;
    if (!parsed.contains("drop_count") && parsed.contains("dropped_events"))
      parsed["drop_count"] = parsed["dropped_events"];
    if (!parsed.contains("drop_count"))
      parsed["drop_count"] = 0;
    if (!parsed.contains("policy_ref"))
      parsed["policy_ref"] = state_impl_.policy_hash();
    if (!parsed.contains("masked_fields") || !parsed["masked_fields"].is_array())
      parsed["masked_fields"] = nlohmann::json::array();

    if (!config_.kernel_allow_raw_sensitive)
    {
      const std::unordered_set<std::string> sensitive_keys = {
          "path", "raw_path", "process_path", "command_line", "arguments", "args", "raw_identifier"};
      for (const auto &key : sensitive_keys)
      {
        if (parsed.contains(key) && !parsed[key].is_null())
        {
          parsed[key] = "[masked]";
          parsed["masked_fields"].push_back(key);
          masked = true;
        }
      }
      if (parsed.contains("masked_fields") && parsed["masked_fields"].is_array())
      {
        std::unordered_set<std::string> seen;
        nlohmann::json deduped = nlohmann::json::array();
        for (const auto &entry : parsed["masked_fields"])
        {
          if (!entry.is_string())
            continue;
          const auto value = entry.get<std::string>();
          if (seen.insert(value).second)
          {
            deduped.push_back(value);
          }
        }
        parsed["masked_fields"] = deduped;
      }
    }

    return parsed.dump();
  }
  catch (const std::exception &)
  {
    return payload_json;
  }
}

void WsClient::run_disconnected_telemetry_tick(bool extended_scope)
{
  if (suspend_http_fallback_.load(std::memory_order_acquire))
  {
    return;
  }

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
                " kernel_sent=" + std::to_string(telemetry_stats_.kernel_sent) +
                " kernel_queued=" + std::to_string(telemetry_stats_.kernel_queued) +
                " kernel_replayed=" + std::to_string(telemetry_stats_.kernel_replayed) +
                " kernel_dropped=" + std::to_string(telemetry_stats_.kernel_dropped) +
                " kernel_retry=" + std::to_string(telemetry_stats_.kernel_retry) +
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
  std::mutex outbound_send_mutex;
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
  auto queue_kernel_ws_payload = [&](const std::string &ws_telemetry, const std::string &reason) {
    std::string payload;
    std::int64_t seq = 0;
    if (parse_ws_telemetry_to_http_payload(ws_telemetry, payload, seq))
    {
      queue_telemetry_payload(payload, seq, reason);
      return;
    }
    telemetry_stats_.dropped += 1;
    telemetry_stats_.kernel_dropped += 1;
    Logger::log(LogLevel::Warn, "kernel telemetry dropped: invalid envelope for fallback conversion");
  };

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

            {
                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                socket.sendText(auth_message);
            }
            
        } else if (msg->type == ix::WebSocketMessageType::Message) {
            Logger::log(LogLevel::Debug, std::string("received: ") + msg->str);
            try {
                auto parsed = nlohmann::json::parse(msg->str);
                std::string mtype = parsed.value("type", "");
                if (mtype == "AUTH_ACK") {
                    std::string session_id = parsed["body"].value("session_id", "");
                    if (!session_id.empty()) {
                        suspend_http_fallback_.store(false, std::memory_order_release);
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
                            std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                            auto hb = build_signed_heartbeat_json(config_.device_id, session_id, "alive", 120, "ok");
                            if (!hb.empty()) {
                                socket.sendText(hb);
                                heartbeat_sent_ = true;
                                telemetry_stats_.sent += 1;
                            }
                        }
                        if (!telemetry_sent_) {
                            {
                                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                auto tel = build_signed_telemetry_json(
                                    config_.device_id,
                                    session_id,
                                    "telemetry_extended",
                                    state_impl_.policy_hash());
                                if (!tel.empty()) {
                                    socket.sendText(tel);
                                    telemetry_sent_ = true;
                                    telemetry_stats_.sent += 1;
                                }
                            }
                            replay_queued_telemetry();
                        }
                        if (is_kernel_driver_enabled() && !kernel_listener_started.load()) {
                            const std::string session_id_copy = session_id;
                            bool started = kernel_listener.start([&, session_id_copy](const KernelEvent &evt) {
                                bool payload_masked = false;
                                std::string kernel_category;
                                const auto normalized_payload = normalize_kernel_payload_json(evt.payload_json, kernel_category, payload_masked);
                                if (!kernel_category_enabled(kernel_category))
                                {
                                    Logger::log(LogLevel::Debug, "kernel telemetry skipped by tier/category policy: " + kernel_category);
                                    return;
                                }
                                if (!kernel_category_sampled(kernel_category))
                                {
                                    return;
                                }
                                kernel_category_seen_[kernel_category] += 1;

                                auto tel = build_signed_kernel_event_telemetry_json(
                                    config_.device_id,
                                    session_id_copy,
                                    evt.event_id,
                                    evt.event_type,
                                    evt.timestamp_unix,
                                    normalized_payload);
                                if (tel.empty()) {
                                    telemetry_stats_.dropped += 1;
                                    telemetry_stats_.kernel_dropped += 1;
                                    Logger::log(LogLevel::Warn, "kernel telemetry dropped: failed to build signed payload");
                                    return;
                                }
                                if (payload_masked)
                                {
                                  Logger::log(LogLevel::Debug, "kernel telemetry payload masked before send");
                                }
                                const bool ws_ready =
                                    connection_opened.load(std::memory_order_acquire) &&
                                    !connection_closed.load(std::memory_order_acquire) &&
                                    !connection_error.load(std::memory_order_acquire) &&
                                    authenticated.load(std::memory_order_acquire);
                                if (ws_ready) {
                                    try {
                                        std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                        socket.sendText(tel);
                                        telemetry_stats_.sent += 1;
                                        telemetry_stats_.kernel_sent += 1;
                                        return;
                                    } catch (const std::exception &) {
                                        Logger::log(LogLevel::Warn, "kernel telemetry WSS send failed; queueing for replay");
                                    }
                                }
                                queue_kernel_ws_payload(tel, ws_ready ? "kernel_ws_send_failed" : "kernel_ws_unavailable");
                            });
                            if (started) {
                                kernel_listener_started.store(true);
                                Logger::log(LogLevel::Info, "kernel event listener started");
                            }
                        }
                    }
                } else if (mtype == "AUTH_ERROR") {
                    auto body = parsed.value("body", nlohmann::json::object());
                    const std::string errorCode = body.value("error_code", "AUTH_ERROR");
                    const std::string errorMessage = body.value("error_message", "");
                    Logger::log(LogLevel::Error, "AUTH_ERROR from gateway: " + errorCode +
                                                  (errorMessage.empty() ? "" : (" - " + errorMessage)));
                    if (errorCode == "AUTH_INVALID_JWT" || errorCode == "AUTH_UNKNOWN_DEVICE") {
                        suspend_http_fallback_.store(true, std::memory_order_release);
                    }
                    close_reason = "auth_error:" + errorCode;
                    connection_error.store(true, std::memory_order_release);
                } else if (mtype == "POLICY_UPDATE") {
                    auto body = parsed["body"];
                    std::string policy_hash = body.value("policy_hash", "");
                    state_impl_.set_policy_hash(policy_hash);
                    Logger::log(LogLevel::Info, "policy updated: " + policy_hash);

                    if (body.contains("app_lock")) {
                        IoctlClient policy_client;
                        const std::string request_id = "policy-applock-" + std::to_string(static_cast<long long>(std::time(nullptr)));

                        if (body["app_lock"].is_null()) {
                            auto clear_res = policy_client.applock_clear_policy(request_id, state_impl_);
                            if (clear_res.status == "ok") {
                                last_good_app_lock_policy_blob_.clear();
                                Logger::log(LogLevel::Info, "app_lock policy cleared via POLICY_UPDATE");
                                auto status_res = policy_client.applock_get_status(request_id + "-status", state_impl_);
                                if (status_res.status == "ok" && !status_res.result.empty()) {
                                    Logger::log(LogLevel::Info, "app_lock kernel status after clear: " + status_res.result);
                                } else if (status_res.status != "ok") {
                                    Logger::log(LogLevel::Warn, "app_lock status readback after clear failed: " + status_res.error_message);
                                }
                            } else {
                                Logger::log(LogLevel::Error, "app_lock clear failed: " + clear_res.error_message);
                            }
                        } else {
                            std::string blob;
                            std::string build_error;
                            if (!build_app_lock_policy_blob(body["app_lock"], policy_hash, blob, build_error)) {
                                Logger::log(LogLevel::Warn, "app_lock policy ignored: " + build_error);
                            } else {
                                auto apply_res = policy_client.applock_replace_policy(request_id, state_impl_, blob);
                                if (apply_res.status == "ok") {
                                    last_good_app_lock_policy_blob_ = blob;
                                    Logger::log(LogLevel::Info, "app_lock policy applied (kernel) successfully");
                                    auto status_res = policy_client.applock_get_status(request_id + "-status", state_impl_);
                                    if (status_res.status == "ok" && !status_res.result.empty()) {
                                        Logger::log(LogLevel::Info, "app_lock kernel status after apply: " + status_res.result);
                                    } else if (status_res.status != "ok") {
                                        Logger::log(LogLevel::Warn, "app_lock status readback after apply failed: " + status_res.error_message);
                                    }
                                } else {
                                    Logger::log(LogLevel::Error, "app_lock apply failed: " + apply_res.error_message);
                                    if (!last_good_app_lock_policy_blob_.empty()) {
                                        auto rollback_res = policy_client.applock_replace_policy(
                                            request_id + "-rollback",
                                            state_impl_,
                                            last_good_app_lock_policy_blob_);
                                        if (rollback_res.status == "ok") {
                                            Logger::log(LogLevel::Warn, "app_lock rollback to last-known-good succeeded");
                                        } else {
                                            Logger::log(LogLevel::Error, "app_lock rollback failed: " + rollback_res.error_message);
                                        }
                                    }
                                }
                            }
                        }
                    }
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
                                {
                                    std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                    auto rejected_ack = build_command_ack_json(config_.device_id, session_id, command_message_id, 
                                                                               "rejected", verify_result.error_code);
                                    if (!rejected_ack.empty()) {
                                        socket.sendText(rejected_ack);
                                    }
                                }
                                
                                // Send error result
                                int error_code = 4003;
                                if (verify_result.error_code == "TTL_EXPIRED") error_code = 4005;
                                else if (verify_result.error_code == "SEQ_REPLAY") error_code = 4006;
                                
                                {
                                    std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                    auto denied = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                            trace_id, "failed", verify_result.error_code,
                                                                            verify_result.error_message, "", "", error_code, "");
                                    if (!denied.empty()) {
                                        socket.sendText(denied);
                                    }
                                }
                                return;
                            }
                            
                            // Update last sequence on successful verification
                            std::uint64_t new_seq = envelope.value("seq", static_cast<std::uint64_t>(0));
                            if (new_seq > last_command_seq_) {
                                last_command_seq_ = new_seq;
                            }
                            
                            Logger::log(LogLevel::Debug, "COMMAND_DELIVERY signature verified successfully");
                        }
                        
                        {
                            std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                            auto ack = build_command_ack_json(config_.device_id, session_id, command_message_id, "received", "");
                            if (!ack.empty()) {
                                socket.sendText(ack);
                            }
                        }

                        if (quarantine_.is_quarantined() && !quarantine_.is_allowed(method)) {
                            {
                                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                auto denied = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                        trace_id, "failed", "denied",
                                                                        "quarantined", "", "", 4001,
                                                                        quarantine_.reason());
                                if (!denied.empty()) {
                                    socket.sendText(denied);
                                }
                            }
                            return;
                        }

                        if (!policy_hash.empty() && !state_impl_.policy_hash().empty() && policy_hash != state_impl_.policy_hash()) {
                            {
                                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                auto denied = build_command_result_json(config_.device_id, session_id, command_message_id,
                                                                        trace_id, "failed", "policy_mismatch",
                                                                        "policy hash mismatch", "", "", 4002, "");
                                if (!denied.empty()) {
                                    socket.sendText(denied);
                                }
                            }
                            return;
                        }

                        nlohmann::json params_obj = envelope["body"].value("params", nlohmann::json::object());
                        const std::string params_json = params_obj.dump();

                        if (command::IsObservabilityMethod(method)) {
                            const auto obs = command::ExecuteObservabilityCommand(
                                config_,
                                state_impl_,
                                method,
                                command_message_id,
                                params_json);
                            if (obs.success) {
                                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                auto result_msg = build_command_result_json(
                                    config_.device_id,
                                    session_id,
                                    command_message_id,
                                    trace_id,
                                    "completed",
                                    "ok",
                                    obs.notes.empty() ? "observability command completed" : obs.notes,
                                    obs.artifact_url,
                                    obs.artifact_checksum,
                                    0,
                                    "",
                                    obs.output_text,
                                    obs.data_json,
                                    obs.meta_json);
                                if (!result_msg.empty()) {
                                    socket.sendText(result_msg);
                                }
                            } else {
                                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                auto result_msg = build_command_result_json(
                                    config_.device_id,
                                    session_id,
                                    command_message_id,
                                    trace_id,
                                    "failed",
                                    "failed",
                                    obs.notes.empty() ? "observability command failed" : obs.notes,
                                    obs.artifact_url,
                                    obs.artifact_checksum,
                                    obs.error_code,
                                    obs.reason,
                                    obs.output_text,
                                    obs.data_json,
                                    obs.meta_json);
                                if (!result_msg.empty()) {
                                    socket.sendText(result_msg);
                                }
                            }
                            return;
                        }

                        if (command::IsScreenshotMethod(method)) {
                            {
                                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                auto progress_msg = build_command_result_json(
                                    config_.device_id,
                                    session_id,
                                    command_message_id,
                                    trace_id,
                                    "executing",
                                    "in_progress",
                                    "screenshot capture started");
                                if (!progress_msg.empty()) {
                                    socket.sendText(progress_msg);
                                }
                            }

                            const auto shot = command::ExecuteScreenshotCommand(
                                config_,
                                state_impl_,
                                command_message_id,
                                params_json);
                            if (shot.success) {
                                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                auto result_msg = build_command_result_json(
                                    config_.device_id,
                                    session_id,
                                    command_message_id,
                                    trace_id,
                                    "completed",
                                    "ok",
                                    shot.notes.empty() ? "screenshot captured" : shot.notes,
                                    shot.artifact_url,
                                    shot.artifact_checksum,
                                    0,
                                    "",
                                    shot.output_text,
                                    shot.data_json,
                                    shot.meta_json);
                                if (!result_msg.empty()) {
                                    socket.sendText(result_msg);
                                }
                            } else {
                                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                auto result_msg = build_command_result_json(
                                    config_.device_id,
                                    session_id,
                                    command_message_id,
                                    trace_id,
                                    "failed",
                                    "failed",
                                    shot.notes.empty() ? "screenshot capture failed" : shot.notes,
                                    "",
                                    "",
                                    shot.error_code,
                                    shot.reason,
                                    shot.output_text,
                                    shot.data_json,
                                    shot.meta_json);
                                if (!result_msg.empty()) {
                                    socket.sendText(result_msg);
                                }
                            }
                            return;
                        }

                        if (command::IsLockScreenMethod(method)) {
                            Logger::log(
                                LogLevel::Info,
                                "lock_screen command received: " + command_message_id);
                            {
                                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                auto progress_msg = build_command_result_json(
                                    config_.device_id,
                                    session_id,
                                    command_message_id,
                                    trace_id,
                                    "executing",
                                    "in_progress",
                                    "lock screen started");
                                if (!progress_msg.empty()) {
                                    socket.sendText(progress_msg);
                                }
                            }

                            // Emit terminal state before lock execution to avoid command rows
                            // getting stuck in "dispatched" when desktop/session transitions
                            // immediately interrupt websocket delivery.
                            {
                                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                auto result_msg = build_command_result_json(
                                    config_.device_id,
                                    session_id,
                                    command_message_id,
                                    trace_id,
                                    "completed",
                                    "ok",
                                    "lock screen request accepted",
                                    "",
                                    "",
                                    0,
                                    "");
                                if (!result_msg.empty()) {
                                    socket.sendText(result_msg);
                                }
                            }

                            const AgentState state_snapshot = state_impl_;
                            const std::string lock_request_id = command_message_id;
                            const std::string lock_params = params_json;
                            std::thread([state_snapshot, lock_request_id, lock_params]() {
                                Logger::log(
                                    LogLevel::Info,
                                    "lock_screen background execution started: " + lock_request_id);
                                const auto locked = command::ExecuteLockScreenCommand(
                                    state_snapshot,
                                    lock_request_id,
                                    lock_params);
                                if (locked.success) {
                                    Logger::log(
                                        LogLevel::Info,
                                        "lock_screen background execution succeeded: " + lock_request_id);
                                } else {
                                    Logger::log(
                                        LogLevel::Warn,
                                        "lock_screen background execution failed: " + lock_request_id +
                                            " reason=" + locked.reason +
                                            " code=" + std::to_string(locked.error_code) +
                                            " notes=" + locked.notes);
                                }
                            }).detach();
                            return;
                        }

                        CommandDispatcher dispatcher;
                        auto res = dispatcher.dispatch(
                            method,
                            command_message_id,
                            state_impl_,
                            params_json,
                            command_message_id);

                        nlohmann::json result_meta = nlohmann::json::object();
                        if (!res.request_id.empty()) {
                            result_meta["request_id"] = res.request_id;
                        }
                        if (!res.kernel_exec_id.empty()) {
                            result_meta["kernel_exec_id"] = res.kernel_exec_id;
                        }
                        if (!res.timestamp.empty()) {
                            result_meta["kernel_timestamp"] = res.timestamp;
                        }
                        result_meta["transport"] = "kernel_ioctl";
                        const std::string meta_json = result_meta.empty() ? std::string() : result_meta.dump();

                        if (res.status == "ok") {
                            const auto parsed_output = parse_command_output_payload(res.result);
                            {
                                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                auto result_msg = build_command_result_json(
                                    config_.device_id, session_id, command_message_id, trace_id,
                                    "completed", "ok", parsed_output.notes, "", "",
                                    res.error_code, res.error_message,
                                    parsed_output.output_text, parsed_output.data_json, meta_json);
                                if (!result_msg.empty()) {
                                    socket.sendText(result_msg);
                                }
                            }
                        } else {
                            const bool unsupported = (res.status == "invalid_opcode" || res.error_code == 4004 || res.error_code == 4002);
                            const auto parsed_output = parse_command_output_payload(res.result);
                            const std::string notes = res.error_message.empty()
                                ? (parsed_output.notes.empty() ? "command execution failed" : parsed_output.notes)
                                : res.error_message;
                            {
                                std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                                auto result_msg = build_command_result_json(
                                    config_.device_id, session_id, command_message_id, trace_id,
                                    "failed",
                                    unsupported ? "unsupported" : "kernel_transport_error",
                                    notes,
                                    "", "",
                                    res.error_code,
                                    res.error_message,
                                    parsed_output.output_text,
                                    parsed_output.data_json,
                                    meta_json);
                                if (!result_msg.empty()) {
                                    socket.sendText(result_msg);
                                }
                            }
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
                        {
                            std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
                            auto status_msg = build_update_status_json(
                                config_.device_id, session_id, release_id, "precheck", version, 0, "acknowledged", 0, "", "");
                            if (!status_msg.empty()) {
                                socket.sendText(status_msg);
                            }
                        }
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
          std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
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
          std::lock_guard<std::mutex> send_guard(outbound_send_mutex);
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
                  " kernel_sent=" + std::to_string(telemetry_stats_.kernel_sent) +
                  " kernel_queued=" + std::to_string(telemetry_stats_.kernel_queued) +
                  " kernel_replayed=" + std::to_string(telemetry_stats_.kernel_replayed) +
                  " kernel_dropped=" + std::to_string(telemetry_stats_.kernel_dropped) +
                  " kernel_retry=" + std::to_string(telemetry_stats_.kernel_retry) +
                  " kernel_exec=" + std::to_string(kernel_category_seen_["exec"]) +
                  " kernel_integrity=" + std::to_string(kernel_category_seen_["integrity"]) +
                  " kernel_attestation=" + std::to_string(kernel_category_seen_["attestation"]) +
                  " kernel_update=" + std::to_string(kernel_category_seen_["update"]) +
                  " kernel_runtime=" + std::to_string(kernel_category_seen_["runtime"]) +
                  (telemetry_stats_.last_success_ts.empty() ? "" : (" last_success=" + telemetry_stats_.last_success_ts)));
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
