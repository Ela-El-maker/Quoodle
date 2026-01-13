#include "ws_protocol.hpp"
#include "../telemetry/telemetry_collector.hpp"
#include <chrono>
#include <random>
#include <sstream>

#include "../utils/json_canonicalizer.hpp"

#include "sequence_manager.hpp"
#include "../crypto/ed25519_sign.hpp"

// Global or static collector instance to track deltas across samples
static TelemetryCollector g_collector;

static SequenceManager &seq_manager()
{
    static SequenceManager mgr(default_sequence_path());
    return mgr;
}

static std::uint64_t next_seq()
{
    return seq_manager().next();
}

namespace
{

    std::string generate_uuid()
    {
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<uint32_t> dis(0, 0xFFFFFFFF);
        uint32_t data[4] = {dis(gen), dis(gen), dis(gen), dis(gen)};

        data[1] = (data[1] & 0xFFFF0FFF) | 0x00004000; // version 4
        data[2] = (data[2] & 0x3FFFFFFF) | 0x80000000; // variant

        std::ostringstream oss;
        oss << std::hex;
        oss.width(8);
        oss.fill('0');
        oss << data[0] << "-";
        oss.width(4);
        oss << (data[1] >> 16) << "-";
        oss.width(4);
        oss << (data[1] & 0xFFFF) << "-";
        oss.width(4);
        oss << (data[2] >> 16) << "-";
        oss.width(4);
        oss << (data[2] & 0xFFFF);
        oss.width(8);
        oss << data[3];
        return oss.str();
    }

    std::string iso_timestamp()
    {
        using namespace std::chrono;
        auto now = system_clock::now();
        auto seconds = time_point_cast<std::chrono::seconds>(now);
        auto subseconds = duration_cast<std::chrono::nanoseconds>(now - seconds).count();
        std::time_t t = system_clock::to_time_t(now);
        std::tm tm{};
#ifdef _WIN32
        gmtime_s(&tm, &t);
#else
        gmtime_r(&t, &tm);
#endif
        char buffer[64];
        std::snprintf(buffer, sizeof(buffer), "%04d-%02d-%02dT%02d:%02d:%02dZ",
                      tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
                      tm.tm_hour, tm.tm_min, tm.tm_sec);
        (void)subseconds;
        return std::string(buffer);
    }

    std::string random_nonce()
    {
        std::random_device rd;
        std::mt19937_64 gen(rd());
        std::uniform_int_distribution<uint64_t> dis;
        std::ostringstream oss;
        oss << dis(gen);
        return oss.str();
    }

} // namespace

AuthEnvelope build_auth_envelope(const std::string &device_id, const std::string &jwt_token)
{
    AuthEnvelope env;
    env.device_id = device_id;
    env.message_id = generate_uuid();
    env.seq = next_seq();
    env.timestamp = iso_timestamp();
    env.body.jwt = jwt_token;
    env.body.nonce = random_nonce();
    env.sig = "";
    return env;
}

std::string canonical_auth_without_sig(const AuthEnvelope &env)
{
    using utils::canonical_object;
    using utils::escape_json;

    std::string agent_info = canonical_object({
        {"agent_version", "\"" + escape_json(env.body.agent_info.agent_version) + "\""},
        {"attestation_hash", "\"" + escape_json(env.body.agent_info.attestation_hash) + "\""},
        {"hwid_hash", "\"" + escape_json(env.body.agent_info.hwid_hash) + "\""},
        {"os_build", "\"" + escape_json(env.body.agent_info.os_build) + "\""},
    });

    std::string auth = canonical_object({
        {"jwt", "\"" + escape_json(env.body.jwt) + "\""},
        {"nonce", "\"" + escape_json(env.body.nonce) + "\""},
    });

    std::string body = canonical_object({
        {"agent_info", agent_info},
        {"auth", auth},
    });

    // Lexicographic order: body, device_id, from, message_id, seq, session_id, timestamp, type
    std::string session_id_value = (env.session_id == "null") ? "null" : "\"" + escape_json(env.session_id) + "\"";

    return canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(env.device_id) + "\""},
        {"from", "\"" + escape_json(env.from) + "\""},
        {"message_id", "\"" + escape_json(env.message_id) + "\""},
        {"seq", std::to_string(env.seq)},
        {"session_id", session_id_value},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
        {"type", "\"" + escape_json(env.type) + "\""},
    });
}

std::string sign_placeholder(const std::string &canonical_json)
{
    return ed25519_sign_payload(canonical_json);
}

std::string build_signed_auth_json(AuthEnvelope envelope)
{
    // 1. Generate the canonical string for the body first
    // 2. Sign it
    // 3. Build the final envelope

    using utils::canonical_object;
    using utils::escape_json;

    // Helper for null/string handling
    auto json_val = [](const std::string &s)
    {
        return (s == "null" || s.empty()) ? "null" : "\"" + escape_json(s) + "\"";
    };

    // Construct Body
    std::string agent_info = canonical_object({
        {"agent_version", "\"" + escape_json(envelope.body.agent_info.agent_version) + "\""},
        {"attestation_hash", "\"" + escape_json(envelope.body.agent_info.attestation_hash) + "\""},
        {"hwid_hash", "\"" + escape_json(envelope.body.agent_info.hwid_hash) + "\""},
        {"os_build", "\"" + escape_json(envelope.body.agent_info.os_build) + "\""},
    });

    std::string auth = canonical_object({
        {"jwt", "\"" + escape_json(envelope.body.jwt) + "\""},
        {"nonce", "\"" + escape_json(envelope.body.nonce) + "\""},
    });

    std::string body = canonical_object({
        {"agent_info", agent_info},
        {"auth", auth},
    });

    // Generate Signature on the data WITHOUT the signature field
    envelope.sig = sign_placeholder(canonical_auth_without_sig(envelope));
    if (envelope.sig.empty())
    {
        return {};
    }

    // Final Envelope (Alphabetical order is mandatory for some backends)
    return canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(envelope.device_id) + "\""},
        {"from", "\"" + escape_json(envelope.from) + "\""},
        {"message_id", "\"" + escape_json(envelope.message_id) + "\""},
        {"seq", std::to_string(envelope.seq)},
        {"session_id", json_val(envelope.session_id)},
        {"sig", "\"" + escape_json(envelope.sig) + "\""},
        {"timestamp", "\"" + escape_json(envelope.timestamp) + "\""},
        {"type", "\"" + escape_json(envelope.type) + "\""},
    });
}

std::string build_signed_heartbeat_json(const std::string &device_id,
                                        const std::string &session_id,
                                        const std::string &status,
                                        int uptime_seconds,
                                        const std::string &error_state)
{
    using utils::canonical_object;
    using utils::escape_json;

    AuthEnvelope env;
    env.type = "HEARTBEAT";
    env.device_id = device_id;
    env.session_id = session_id;
    env.message_id = generate_uuid();
    env.seq = next_seq();
    env.timestamp = iso_timestamp();
    env.sig = "";

    std::string body = canonical_object({
        {"error_state", "\"" + escape_json(error_state) + "\""},
        {"status", "\"" + escape_json(status) + "\""},
        {"uptime_seconds", std::to_string(uptime_seconds)},
    });

    std::string canonical = canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(env.device_id) + "\""},
        {"from", "\"" + escape_json(env.from) + "\""},
        {"message_id", "\"" + escape_json(env.message_id) + "\""},
        {"seq", std::to_string(env.seq)},
        {"session_id", "\"" + escape_json(env.session_id) + "\""},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
        {"type", "\"" + escape_json(env.type) + "\""},
    });

    env.sig = sign_placeholder(canonical);
    if (env.sig.empty())
    {
        return {};
    }

    return canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(env.device_id) + "\""},
        {"from", "\"" + escape_json(env.from) + "\""},
        {"message_id", "\"" + escape_json(env.message_id) + "\""},
        {"seq", std::to_string(env.seq)},
        {"session_id", "\"" + escape_json(env.session_id) + "\""},
        {"sig", "\"" + escape_json(env.sig) + "\""},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
        {"type", "\"" + escape_json(env.type) + "\""},
    });
}

std::string build_update_status_json(const std::string &device_id,
                                     const std::string &session_id,
                                     const std::string &release_id,
                                     const std::string &phase,
                                     const std::string &version,
                                     int progress_percent,
                                     const std::string &progress_detail,
                                     int error_code,
                                     const std::string &error_message,
                                     const std::string &rollback_snapshot_id)
{
    using utils::canonical_object;
    using utils::escape_json;

    AuthEnvelope env;
    env.type = "UPDATE_STATUS";
    env.device_id = device_id;
    env.session_id = session_id;
    env.message_id = generate_uuid();
    env.seq = next_seq();
    env.timestamp = iso_timestamp();
    env.sig = "";

    // Body keys must be lexicographic to match FastAPI canonicalization.
    std::string body = canonical_object({
        {"error_code", error_code == 0 ? "null" : std::to_string(error_code)},
        {"error_message", error_message.empty() ? "null" : "\"" + escape_json(error_message) + "\""},
        {"phase", "\"" + escape_json(phase) + "\""},
        {"progress", canonical_object({
                         {"detail", "\"" + escape_json(progress_detail) + "\""},
                         {"percent", std::to_string(progress_percent)},
                     })},
        {"release_id", "\"" + escape_json(release_id) + "\""},
        {"rollback_snapshot_id", rollback_snapshot_id.empty() ? "null" : "\"" + escape_json(rollback_snapshot_id) + "\""},
        {"version", "\"" + escape_json(version) + "\""},
    });

    std::string canonical = canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(env.device_id) + "\""},
        {"from", "\"" + escape_json(env.from) + "\""},
        {"message_id", "\"" + escape_json(env.message_id) + "\""},
        {"seq", std::to_string(env.seq)},
        {"session_id", "\"" + escape_json(env.session_id) + "\""},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
        {"type", "\"" + escape_json(env.type) + "\""},
    });

    env.sig = sign_placeholder(canonical);
    if (env.sig.empty())
    {
        return {};
    }

    return canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(env.device_id) + "\""},
        {"from", "\"" + escape_json(env.from) + "\""},
        {"message_id", "\"" + escape_json(env.message_id) + "\""},
        {"seq", std::to_string(env.seq)},
        {"session_id", "\"" + escape_json(env.session_id) + "\""},
        {"sig", "\"" + escape_json(env.sig) + "\""},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
        {"type", "\"" + escape_json(env.type) + "\""},
    });
}

std::string build_signed_telemetry_json(const std::string &device_id,
                                        const std::string &session_id)
{
    using utils::canonical_object;
    using utils::escape_json;

    AuthEnvelope env;
    env.type = "TELEMETRY";
    env.device_id = device_id;
    env.session_id = session_id;
    env.from = "agent";
    env.message_id = generate_uuid();
    env.seq = next_seq();
    env.timestamp = iso_timestamp();

    // Fetch real metrics
    auto sample = g_collector.collect();

    std::string metrics = canonical_object({
        {"cpu", "\"" + escape_json(sample.cpu) + "\""},
        {"disk_usage", "\"" + escape_json(sample.disk) + "\""},
        {"network_rx", "\"" + escape_json(sample.network_rx) + "\""},
        {"network_tx", "\"" + escape_json(sample.network_tx) + "\""},
        {"ram", "\"" + escape_json(sample.ram) + "\""},
    });

    std::string body = canonical_object({
        {"metrics", metrics},
        {"telemetry_scope", "\"telemetry_basic\""},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
    });

    std::string canonical = canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(env.device_id) + "\""},
        {"from", "\"" + escape_json(env.from) + "\""},
        {"message_id", "\"" + escape_json(env.message_id) + "\""},
        {"seq", std::to_string(env.seq)},
        {"session_id", "\"" + escape_json(env.session_id) + "\""},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
        {"type", "\"" + escape_json(env.type) + "\""},
    });

    env.sig = sign_placeholder(canonical);
    if (env.sig.empty())
    {
        return {};
    }

    return canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(env.device_id) + "\""},
        {"from", "\"" + escape_json(env.from) + "\""},
        {"message_id", "\"" + escape_json(env.message_id) + "\""},
        {"seq", std::to_string(env.seq)},
        {"session_id", "\"" + escape_json(env.session_id) + "\""},
        {"sig", "\"" + escape_json(env.sig) + "\""},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
        {"type", "\"" + escape_json(env.type) + "\""},
    });
}

std::string build_command_ack_json(const std::string &device_id,
                                   const std::string &session_id,
                                   const std::string &command_message_id,
                                   const std::string &status,
                                   const std::string &reason)
{
    using utils::canonical_object;
    using utils::escape_json;

    AuthEnvelope env;
    env.type = "COMMAND_ACK";
    env.device_id = device_id;
    env.session_id = session_id;
    env.message_id = generate_uuid();
    env.seq = next_seq();
    env.timestamp = iso_timestamp();
    env.sig = "";

    std::string body = canonical_object({
        {"command_message_id", "\"" + escape_json(command_message_id) + "\""},
        {"reason", reason.empty() ? "null" : "\"" + escape_json(reason) + "\""},
        {"status", "\"" + escape_json(status) + "\""},
    });

    std::string canonical = canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(env.device_id) + "\""},
        {"from", "\"" + escape_json(env.from) + "\""},
        {"message_id", "\"" + escape_json(env.message_id) + "\""},
        {"seq", std::to_string(env.seq)},
        {"session_id", "\"" + escape_json(env.session_id) + "\""},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
        {"type", "\"" + escape_json(env.type) + "\""},
    });

    env.sig = sign_placeholder(canonical);
    if (env.sig.empty())
    {
        return {};
    }

    return canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(env.device_id) + "\""},
        {"from", "\"" + escape_json(env.from) + "\""},
        {"message_id", "\"" + escape_json(env.message_id) + "\""},
        {"seq", std::to_string(env.seq)},
        {"session_id", "\"" + escape_json(env.session_id) + "\""},
        {"sig", "\"" + escape_json(env.sig) + "\""},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
        {"type", "\"" + escape_json(env.type) + "\""},
    });
}

std::string build_command_result_json(const std::string &device_id,
                                      const std::string &session_id,
                                      const std::string &command_message_id,
                                      const std::string &trace_id,
                                      const std::string &execution_state,
                                      const std::string &result_status,
                                      const std::string &notes,
                                      const std::string &artifact_url,
                                      const std::string &artifact_checksum,
                                      int error_code,
                                      const std::string &error_message)
{
    using utils::canonical_object;
    using utils::escape_json;

    AuthEnvelope env;
    env.type = "COMMAND_RESULT";
    env.device_id = device_id;
    env.session_id = session_id;
    env.message_id = generate_uuid();
    env.seq = next_seq();
    env.timestamp = iso_timestamp();
    env.sig = "";

    std::string result_obj = canonical_object({
        {"artifact_checksum", artifact_checksum.empty() ? "null" : "\"" + escape_json(artifact_checksum) + "\""},
        {"artifact_url", artifact_url.empty() ? "null" : "\"" + escape_json(artifact_url) + "\""},
        {"notes", "\"" + escape_json(notes) + "\""},
        {"status", "\"" + escape_json(result_status) + "\""},
    });

    std::string error_code_val = error_code == 0 ? "null" : std::to_string(error_code);
    std::string error_message_val = error_message.empty() ? "null" : "\"" + escape_json(error_message) + "\"";

    // Body keys must be lexicographic to match FastAPI canonicalization.
    std::string body = canonical_object({
        {"command_message_id", "\"" + escape_json(command_message_id) + "\""},
        {"error_code", error_code_val},
        {"error_message", error_message_val},
        {"execution_state", "\"" + escape_json(execution_state) + "\""},
        {"result", result_obj},
        {"trace_id", trace_id.empty() ? "null" : "\"" + escape_json(trace_id) + "\""},
    });

    std::string canonical = canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(env.device_id) + "\""},
        {"from", "\"" + escape_json(env.from) + "\""},
        {"message_id", "\"" + escape_json(env.message_id) + "\""},
        {"seq", std::to_string(env.seq)},
        {"session_id", "\"" + escape_json(env.session_id) + "\""},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
        {"type", "\"" + escape_json(env.type) + "\""},
    });

    env.sig = sign_placeholder(canonical);
    if (env.sig.empty())
    {
        return {};
    }

    return canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(env.device_id) + "\""},
        {"from", "\"" + escape_json(env.from) + "\""},
        {"message_id", "\"" + escape_json(env.message_id) + "\""},
        {"seq", std::to_string(env.seq)},
        {"session_id", "\"" + escape_json(env.session_id) + "\""},
        {"sig", "\"" + escape_json(env.sig) + "\""},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
        {"type", "\"" + escape_json(env.type) + "\""},
    });
}
