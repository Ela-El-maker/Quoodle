#pragma once

#include <string>
#include <cstdint>

/**
 * Reconnection configuration with exponential backoff.
 */
struct ReconnectionConfig
{
    /// Initial delay before first reconnection attempt (milliseconds)
    std::uint32_t initial_delay_ms{1000};

    /// Maximum delay between reconnection attempts (milliseconds)
    std::uint32_t max_delay_ms{60000};

    /// Multiplier for exponential backoff (e.g., 2.0 doubles delay each attempt)
    double backoff_multiplier{2.0};

    /// Maximum number of reconnection attempts (0 = unlimited)
    std::uint32_t max_retries{0};

    /// Jitter factor (0.0-1.0) to randomize delays and avoid thundering herd
    double jitter_factor{0.25};

    /// Whether to reset backoff after successful connection
    bool reset_on_success{true};
};

struct AgentConfig
{
    std::string endpoint{"ws://localhost:8000/agent"};
    std::string device_id{"PC001"};
    std::string jwt;

    /// Reconnection settings
    ReconnectionConfig reconnection;

    /// Keep-alive interval for heartbeats (seconds)
    std::uint32_t heartbeat_interval_s{30};

    /// Telemetry snapshot interval for extended telemetry (seconds)
    std::uint32_t telemetry_interval_s{60};

    /// Enable HTTP telemetry fallback path when WSS is unavailable.
    bool telemetry_http_fallback{true};

    /// Gateway base URL for telemetry HTTP fallback.
    std::string telemetry_fallback_url{"http://localhost:8000"};

    /// Telemetry queue SQLite path used for offline buffering/replay.
    std::string telemetry_queue_db_path{"C:/ProgramData/Quoodle/telemetry_queue.db"};

    /// Max number of telemetry entries drained per replay call.
    std::uint32_t telemetry_batch_size{50};

    /// Max number of telemetry entries retained in queue before oldest drop.
    std::uint32_t telemetry_max_queue_items{5000};

    /// Base retry backoff (seconds) for telemetry replay failures.
    std::uint32_t telemetry_retry_backoff_s{5};

    /// Max retry backoff (seconds) for telemetry replay failures.
    std::uint32_t telemetry_retry_backoff_max_s{300};

    /// Connection timeout (milliseconds)
    std::uint32_t connection_timeout_ms{10000};
};
