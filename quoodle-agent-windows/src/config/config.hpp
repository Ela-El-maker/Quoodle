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

    /// Connection timeout (milliseconds)
    std::uint32_t connection_timeout_ms{10000};
};
