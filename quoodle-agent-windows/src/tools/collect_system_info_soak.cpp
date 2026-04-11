#include "../agent_state.hpp"
#include "../kernel/driver_ioctl.hpp"
#include "../kernel/ioctl_client.hpp"
#include "../logging/logger.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace
{

struct SoakConfig
{
    std::uint32_t duration_seconds{1200};
    std::uint32_t interval_ms{1000};
    std::uint32_t latency_sla_ms{2000};
    std::string output_path{};
};

struct SoakStats
{
    std::uint64_t iterations{0};
    std::uint64_t success{0};
    std::uint64_t failed{0};
    std::uint64_t transport_errors{0};
    std::uint64_t signature_errors{0};
    std::uint64_t version_errors{0};
    std::uint64_t schema_errors{0};
    std::uint64_t fail_open_fallback_events{0};
    std::uint64_t max_payload_bytes{0};
    std::vector<std::uint64_t> latency_ms{};
    std::unordered_map<int, std::uint64_t> error_code_counts{};
    std::unordered_map<int, std::uint64_t> win32_error_counts{};
    std::unordered_map<std::string, std::uint64_t> error_message_counts{};
    bool ping_preflight_ok{false};
    int ping_preflight_error_code{0};
    std::string ping_preflight_error_message{};
};

std::string env_or_default(const char *name, const std::string &default_value)
{
    if (const char *v = std::getenv(name))
    {
        if (*v)
        {
            return std::string(v);
        }
    }
    return default_value;
}

std::uint32_t parse_u32(const char *value, std::uint32_t fallback)
{
    if (!value || !*value)
    {
        return fallback;
    }
    try
    {
        return static_cast<std::uint32_t>(std::stoul(value));
    }
    catch (const std::exception &)
    {
        return fallback;
    }
}

SoakConfig parse_args(int argc, char **argv)
{
    SoakConfig cfg;
    for (int i = 1; i < argc; ++i)
    {
        const std::string arg = argv[i] ? argv[i] : "";
        if (arg == "--duration-seconds" && i + 1 < argc)
        {
            cfg.duration_seconds = parse_u32(argv[++i], cfg.duration_seconds);
            continue;
        }
        if (arg == "--interval-ms" && i + 1 < argc)
        {
            cfg.interval_ms = parse_u32(argv[++i], cfg.interval_ms);
            continue;
        }
        if (arg == "--latency-sla-ms" && i + 1 < argc)
        {
            cfg.latency_sla_ms = parse_u32(argv[++i], cfg.latency_sla_ms);
            continue;
        }
        if (arg == "--output" && i + 1 < argc)
        {
            cfg.output_path = argv[++i] ? argv[i] : "";
            continue;
        }
    }
    return cfg;
}

std::string make_request_id(std::uint64_t iteration)
{
    const auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
                         std::chrono::system_clock::now().time_since_epoch())
                         .count();
    return "collect-system-info-soak-" + std::to_string(now) + "-" + std::to_string(iteration);
}

std::uint64_t percentile_ms(std::vector<std::uint64_t> samples, double percentile)
{
    if (samples.empty())
    {
        return 0;
    }
    std::sort(samples.begin(), samples.end());
    const double clamped = std::max(0.0, std::min(100.0, percentile));
    const std::size_t idx = static_cast<std::size_t>((clamped / 100.0) * static_cast<double>(samples.size() - 1));
    return samples[idx];
}

bool contains_token_case_insensitive(const std::string &value, const std::string &token)
{
    std::string lower_value = value;
    std::string lower_token = token;
    std::transform(lower_value.begin(), lower_value.end(), lower_value.begin(), [](unsigned char c)
                   { return static_cast<char>(std::tolower(c)); });
    std::transform(lower_token.begin(), lower_token.end(), lower_token.begin(), [](unsigned char c)
                   { return static_cast<char>(std::tolower(c)); });
    return lower_value.find(lower_token) != std::string::npos;
}

} // namespace

int main(int argc, char **argv)
{
    const SoakConfig cfg = parse_args(argc, argv);

    const std::string device_id = env_or_default("AGENT_DEVICE_ID", "collect-info-local-device");
    const std::string policy_hash = env_or_default("AGENT_POLICY_HASH", "");

    if (env_or_default("QUOODLE_USE_KERNEL_DRIVER", "0") == "0")
    {
        Logger::log(LogLevel::Warn, "QUOODLE_USE_KERNEL_DRIVER is not enabled; strict KMDF mode is recommended.");
    }
    if (env_or_default("QUOODLE_ALLOW_PIPE_FALLBACK", "0") != "0")
    {
        Logger::log(LogLevel::Warn, "QUOODLE_ALLOW_PIPE_FALLBACK is enabled; strict soak expects this to be 0.");
    }

    AgentState state(device_id);
    state.set_policy_hash(policy_hash);

    IoctlClient ioctl;
    SoakStats stats;
    stats.latency_ms.reserve(static_cast<std::size_t>(cfg.duration_seconds) + 4);

    Logger::log(LogLevel::Info, "Starting collect_system_info soak test.");
    Logger::log(LogLevel::Info, "duration_seconds=" + std::to_string(cfg.duration_seconds) +
                                    " interval_ms=" + std::to_string(cfg.interval_ms) +
                                    " latency_sla_ms=" + std::to_string(cfg.latency_sla_ms));

    {
        const std::string ping_request_id = make_request_id(0) + "-ping";
        const KernelExecResult ping_result = ioctl.ping(ping_request_id, state, "soak-preflight-ping");
        if (ping_result.status == "ok" && ping_result.error_code == 0)
        {
            stats.ping_preflight_ok = true;
        }
        else
        {
            stats.ping_preflight_ok = false;
            stats.ping_preflight_error_code = ping_result.error_code != 0 ? ping_result.error_code : ioctl.last_transport_error_code();
            stats.ping_preflight_error_message =
                !ping_result.error_message.empty() ? ping_result.error_message : ioctl.last_transport_error_message();
            const int ping_win32_error = ioctl.last_transport_win32_error();
            if (ping_win32_error != 0)
            {
                stats.win32_error_counts[ping_win32_error] += 1;
            }
        }
    }

    const auto soak_start = std::chrono::steady_clock::now();
    while (std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() - soak_start).count() <
           cfg.duration_seconds)
    {
        const auto started = std::chrono::steady_clock::now();
        const std::string request_id = make_request_id(stats.iterations + 1);
        const KernelExecResult result = ioctl.collect_system_info(request_id, state, "soak-collect-system-info");
        const auto ended = std::chrono::steady_clock::now();

        const std::uint64_t latency_ms = static_cast<std::uint64_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(ended - started).count());
        stats.latency_ms.push_back(latency_ms);
        stats.iterations += 1;

        if (ioctl.using_pipe_transport())
        {
            stats.fail_open_fallback_events += 1;
        }

        if (result.status == "ok" && result.error_code == 0)
        {
            try
            {
                const auto parsed = nlohmann::json::parse(result.result);
                if (!parsed.is_object())
                {
                    stats.failed += 1;
                    stats.schema_errors += 1;
                }
                else
                {
                    stats.success += 1;
                    stats.max_payload_bytes = std::max<std::uint64_t>(
                        stats.max_payload_bytes,
                        static_cast<std::uint64_t>(result.result.size()));
                }
            }
            catch (const std::exception &)
            {
                stats.failed += 1;
                stats.schema_errors += 1;
            }
        }
        else
        {
            stats.failed += 1;
            int effective_error_code = result.error_code;
            std::string effective_error_message = result.error_message;
            if (effective_error_code == 0)
            {
                effective_error_code = ioctl.last_transport_error_code();
            }
            if (effective_error_message.empty())
            {
                effective_error_message = ioctl.last_transport_error_message();
            }
            stats.error_code_counts[effective_error_code] += 1;
            if (!effective_error_message.empty())
            {
                stats.error_message_counts[effective_error_message] += 1;
            }
            const int win32_error = ioctl.last_transport_win32_error();
            if (win32_error != 0)
            {
                stats.win32_error_counts[win32_error] += 1;
            }

            if (effective_error_code == QERR_INVALID_VERSION ||
                contains_token_case_insensitive(effective_error_message, "invalid_version"))
            {
                stats.version_errors += 1;
            }

            if (effective_error_code == QERR_SIGNATURE_INVALID ||
                effective_error_code == QERR_SIGNATURE_MISSING ||
                contains_token_case_insensitive(effective_error_message, "signature"))
            {
                stats.signature_errors += 1;
            }

            if (effective_error_code < 0 || effective_error_code == 4101 || effective_error_code == 4102 || effective_error_code == 4103)
            {
                stats.transport_errors += 1;
            }
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(cfg.interval_ms));
    }

    const std::uint64_t latency_p95_ms = percentile_ms(stats.latency_ms, 95.0);
    const std::uint64_t latency_max_ms = percentile_ms(stats.latency_ms, 100.0);
    const double latency_avg_ms = stats.latency_ms.empty()
                                      ? 0.0
                                      : static_cast<double>(std::accumulate(stats.latency_ms.begin(), stats.latency_ms.end(), 0ULL)) /
                                            static_cast<double>(stats.latency_ms.size());
    const double success_rate = stats.iterations == 0
                                    ? 0.0
                                    : (100.0 * static_cast<double>(stats.success) / static_cast<double>(stats.iterations));
    const double payload_utilization_pct =
        (100.0 * static_cast<double>(stats.max_payload_bytes) / static_cast<double>(QUOODLE_MAX_RESULT));
    nlohmann::json error_codes_json = nlohmann::json::object();
    nlohmann::json win32_error_codes_json = nlohmann::json::object();
    nlohmann::json error_messages_json = nlohmann::json::object();
    for (const auto &[code, count] : stats.error_code_counts)
    {
        error_codes_json[std::to_string(code)] = count;
    }
    for (const auto &[message, count] : stats.error_message_counts)
    {
        error_messages_json[message] = count;
    }
    for (const auto &[code, count] : stats.win32_error_counts)
    {
        win32_error_codes_json[std::to_string(code)] = count;
    }

    const bool pass =
        stats.iterations > 0 &&
        success_rate >= 99.0 &&
        stats.signature_errors == 0 &&
        stats.version_errors == 0 &&
        stats.fail_open_fallback_events == 0 &&
        latency_p95_ms <= cfg.latency_sla_ms;

    nlohmann::json summary = {
        {"opcode", "collect_system_info"},
        {"duration_seconds", cfg.duration_seconds},
        {"ping_preflight_ok", stats.ping_preflight_ok},
        {"ping_preflight_error_code", stats.ping_preflight_error_code},
        {"ping_preflight_error_message", stats.ping_preflight_error_message},
        {"interval_ms", cfg.interval_ms},
        {"latency_sla_ms", cfg.latency_sla_ms},
        {"iterations", stats.iterations},
        {"success", stats.success},
        {"failed", stats.failed},
        {"success_rate_pct", success_rate},
        {"transport_errors", stats.transport_errors},
        {"signature_errors", stats.signature_errors},
        {"version_errors", stats.version_errors},
        {"schema_errors", stats.schema_errors},
        {"fail_open_fallback_events", stats.fail_open_fallback_events},
        {"error_code_counts", error_codes_json},
        {"win32_error_counts", win32_error_codes_json},
        {"error_message_counts", error_messages_json},
        {"latency_avg_ms", latency_avg_ms},
        {"latency_p95_ms", latency_p95_ms},
        {"latency_max_ms", latency_max_ms},
        {"max_payload_bytes", stats.max_payload_bytes},
        {"max_payload_utilization_pct", payload_utilization_pct},
        {"result_capacity_bytes", QUOODLE_MAX_RESULT},
        {"pass", pass}};

    if (!cfg.output_path.empty())
    {
        std::ofstream out(cfg.output_path, std::ios::trunc);
        if (!out)
        {
            Logger::log(LogLevel::Warn, "Unable to write soak summary file: " + cfg.output_path);
        }
        else
        {
            out << std::setw(2) << summary << std::endl;
            Logger::log(LogLevel::Info, "Wrote soak summary: " + cfg.output_path);
        }
    }

    std::cout << std::setw(2) << summary << std::endl;
    return pass ? 0 : 1;
}
