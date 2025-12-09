#include "ws_protocol.hpp"

#include <chrono>
#include <random>
#include <sstream>

#include "../utils/json_canonicalizer.hpp"

namespace {

std::string generate_uuid() {
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<uint32_t> dis(0, 0xFFFFFFFF);
    uint32_t data[4] = {dis(gen), dis(gen), dis(gen), dis(gen())};

    data[1] = (data[1] & 0xFFFF0FFF) | 0x00004000;  // version 4
    data[2] = (data[2] & 0x3FFFFFFF) | 0x80000000;  // variant

    std::ostringstream oss;
    oss << std::hex;
    oss.width(8); oss.fill('0'); oss << data[0] << "-";
    oss.width(4); oss << (data[1] >> 16) << "-";
    oss.width(4); oss << (data[1] & 0xFFFF) << "-";
    oss.width(4); oss << (data[2] >> 16) << "-";
    oss.width(4); oss << (data[2] & 0xFFFF);
    oss.width(8); oss << data[3];
    return oss.str();
}

std::string iso_timestamp() {
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

std::string random_nonce() {
    std::random_device rd;
    std::mt19937_64 gen(rd());
    std::uniform_int_distribution<uint64_t> dis;
    std::ostringstream oss;
    oss << dis(gen);
    return oss.str();
}

}  // namespace

AuthEnvelope build_auth_envelope(const std::string& device_id, const std::string& jwt_token) {
    AuthEnvelope env;
    env.device_id = device_id;
    env.message_id = generate_uuid();
    env.timestamp = iso_timestamp();
    env.body.jwt = jwt_token;
    env.body.nonce = random_nonce();
    env.sig = "";
    return env;
}

std::string canonical_auth_without_sig(const AuthEnvelope& env) {
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

    // Lexicographic order: body, device_id, from, message_id, session_id, timestamp, type
    std::string session_id_value = (env.session_id == "null") ? "null" : "\"" + escape_json(env.session_id) + "\"";

    return canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(env.device_id) + "\""},
        {"from", "\"" + escape_json(env.from) + "\""},
        {"message_id", "\"" + escape_json(env.message_id) + "\""},
        {"session_id", session_id_value},
        {"timestamp", "\"" + escape_json(env.timestamp) + "\""},
        {"type", "\"" + escape_json(env.type) + "\""},
    });
}

std::string sign_placeholder(const std::string& canonical_json) {
    (void)canonical_json;
    return "sig-placeholder";
}

std::string build_signed_auth_json(AuthEnvelope envelope) {
    auto canonical = canonical_auth_without_sig(envelope);
    envelope.sig = sign_placeholder(canonical);

    using utils::canonical_object;
    using utils::escape_json;

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

    std::string session_id_value = (envelope.session_id == "null") ? "null" : "\"" + escape_json(envelope.session_id) + "\"";

    // Lexicographic order with sig included: body, device_id, from, message_id, session_id, sig, timestamp, type
    return canonical_object({
        {"body", body},
        {"device_id", "\"" + escape_json(envelope.device_id) + "\""},
        {"from", "\"" + escape_json(envelope.from) + "\""},
        {"message_id", "\"" + escape_json(envelope.message_id) + "\""},
        {"session_id", session_id_value},
        {"sig", "\"" + escape_json(envelope.sig) + "\""},
        {"timestamp", "\"" + escape_json(envelope.timestamp) + "\""},
        {"type", "\"" + escape_json(envelope.type) + "\""},
    });
}
