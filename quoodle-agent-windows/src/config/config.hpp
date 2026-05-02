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
    std::string telemetry_fallback_url;

    /// Gateway base URL used for artifact upload APIs.
    std::string artifact_api_base_url;

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

    /// Kernel telemetry tier policy (core|balanced|deep).
    std::string kernel_telemetry_tier{"core"};

    /// Kernel telemetry category toggles (defaults are tier-derived).
    bool kernel_enable_exec{true};
    bool kernel_enable_integrity{false};
    bool kernel_enable_attestation{false};
    bool kernel_enable_update{false};
    bool kernel_enable_runtime{true};

    /// Kernel telemetry per-category sample rates (0..100).
    std::uint32_t kernel_sample_exec_pct{100};
    std::uint32_t kernel_sample_integrity_pct{100};
    std::uint32_t kernel_sample_attestation_pct{100};
    std::uint32_t kernel_sample_update_pct{100};
    std::uint32_t kernel_sample_runtime_pct{100};

    /// Allow raw-sensitive kernel fields (default false for mask-by-default).
    bool kernel_allow_raw_sensitive{false};

    /// Connection timeout (milliseconds)
    std::uint32_t connection_timeout_ms{10000};
};
