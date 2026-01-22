#include "privileged_client.h"

#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <chrono>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <iostream>
#include <random>
#include <string>

#include "crypto.h"
#include "jcs.h"

namespace quoodle {
namespace {

std::string GetEnvOrDefault(const char *name, const char *fallback) {
    const char *value = std::getenv(name);
    if (value && *value) {
        return value;
    }
    return fallback;
}

std::string GenerateUuid() {
    std::ifstream in("/proc/sys/kernel/random/uuid");
    if (in.good()) {
        std::string uuid;
        std::getline(in, uuid);
        if (!uuid.empty()) {
            return uuid;
        }
    }
    std::random_device rd;
    std::uniform_int_distribution<int> dist(0, 15);
    std::string hex = "0123456789abcdef";
    std::string uuid;
    uuid.reserve(36);
    for (int i = 0; i < 36; ++i) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            uuid.push_back('-');
        } else {
            uuid.push_back(hex[dist(rd)]);
        }
    }
    return uuid;
}

std::string BuildIsoTimestamp() {
    auto now = std::chrono::system_clock::now();
    std::time_t tt = std::chrono::system_clock::to_time_t(now);
    std::tm tm{};
    gmtime_r(&tt, &tm);
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tm);
    return buf;
}

std::string StripSigForCanonical(const nlohmann::json &payload) {
    nlohmann::json copy = payload;
    if (copy.contains("sig") && copy["sig"].is_object()) {
        copy["sig"]["sig"] = "";
    }
    return CanonicalizeJcs(copy.dump());
}

bool ReadFrame(int fd, std::string *payload) {
    uint32_t len = 0;
    ssize_t n = read(fd, &len, sizeof(len));
    if (n != sizeof(len)) {
        return false;
    }
    len = ntohl(len);
    if (len == 0 || len > 1024 * 1024) {
        return false;
    }
    std::string buf(len, '\0');
    size_t off = 0;
    while (off < len) {
        ssize_t r = read(fd, buf.data() + off, len - off);
        if (r <= 0) {
            return false;
        }
        off += static_cast<size_t>(r);
    }
    *payload = std::move(buf);
    return true;
}

bool WriteFrame(int fd, const std::string &payload) {
    uint32_t len = htonl(static_cast<uint32_t>(payload.size()));
    if (write(fd, &len, sizeof(len)) != sizeof(len)) {
        return false;
    }
    size_t off = 0;
    while (off < payload.size()) {
        ssize_t w = write(fd, payload.data() + off, payload.size() - off);
        if (w <= 0) {
            return false;
        }
        off += static_cast<size_t>(w);
    }
    return true;
}

ExecutionResult BuildAgentLocalSuccess(const std::string &message) {
    ExecutionResult result;
    result.execution_state = "completed";
    result.status = "ok";
    result.error_type.clear();
    result.error_message.clear();
    result.result = nlohmann::json::object();
    if (!message.empty()) {
        result.result["message"] = message;
    }
    return result;
}

ExecutionResult BuildUnsupportedResult(const std::string &method) {
    ExecutionResult result;
    result.execution_state = "failed";
    result.status = "failed";
    result.error_type = "ERR_CAPABILITY_NOT_SUPPORTED";
    result.error_message = "Unsupported method: " + method;
    result.result = nlohmann::json::object();
    return result;
}

}  // namespace

PrivilegedClient::PrivilegedClient(ReplayCache &replay) : replay_(replay) {}

std::string PrivilegedClient::MapMethodToCapability(const std::string &method) const {
    if (method == "lock_screen") return "CAP_LOCK_SESSION";
    if (method == "reboot" || method == "reboot_device") return "CAP_REBOOT_SYSTEM";
    if (method == "shutdown" || method == "shutdown_device") return "CAP_SHUTDOWN_SYSTEM";
    if (method == "kill_process") return "CAP_TERMINATE_PROCESS";
    if (method == "quarantine") return "CAP_NETWORK_ISOLATION";
    if (method == "attest") return "CAP_ATTESTATION";
    if (method == "ping") return "AGENT_LOCAL";
    if (method == "update_agent" || method == "rotate_keys") return "AGENT_LOCAL";
    if (method == "screenshot" || method == "collect_logs") return "UNSUPPORTED";
    return "UNSUPPORTED";
}

ExecutionResult PrivilegedClient::BuildUnsupported(const std::string &method) const {
    return BuildUnsupportedResult(method);
}

std::string PrivilegedClient::BuildRequestId() const {
    return GenerateUuid();
}

std::string PrivilegedClient::IsoTimestamp() const {
    return BuildIsoTimestamp();
}

bool PrivilegedClient::SendRequest(const nlohmann::json &payload, nlohmann::json *response) const {
    std::string socket_path = GetEnvOrDefault("QUOODLE_PRIV_SOCKET", "/run/quoodle/privileged.sock");
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        return false;
    }
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", socket_path.c_str());
    if (connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) != 0) {
        close(fd);
        return false;
    }
    std::string payload_text = payload.dump();
    if (!WriteFrame(fd, payload_text)) {
        close(fd);
        return false;
    }
    std::string response_text;
    if (!ReadFrame(fd, &response_text)) {
        close(fd);
        return false;
    }
    close(fd);
    try {
        *response = nlohmann::json::parse(response_text);
    } catch (const std::exception &) {
        return false;
    }
    return true;
}

ExecutionResult PrivilegedClient::Execute(const CommandRequest &request) {
    const std::string cap = MapMethodToCapability(request.method);
    if (cap == "UNSUPPORTED") {
        return BuildUnsupported(request.method);
    }
    if (cap == "AGENT_LOCAL") {
        return BuildAgentLocalSuccess("handled locally");
    }

    nlohmann::json payload;
    payload["request_id"] = BuildRequestId();
    payload["timestamp"] = IsoTimestamp();
    payload["capability"] = cap;
    payload["params"] = request.params.is_object() ? request.params : nlohmann::json::object();
    payload["agent_sequence"] = replay_.NextSeq();
    payload["policy_hash"] = request.policy_hash;
    payload["command_message_id"] = request.command_id;

    nlohmann::json sig;
    sig["alg"] = "Ed25519";
    sig["kid"] = GetEnvOrDefault("QUOODLE_AGENT_KID", "agent-default");
    sig["canon"] = "JCS-v1";
    sig["signer"] = "agent";
    sig["sig"] = "";
    payload["sig"] = sig;

    std::string canonical;
    try {
        canonical = StripSigForCanonical(payload);
    } catch (const std::exception &ex) {
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_SCHEMA_INVALID";
        result.error_message = ex.what();
        result.result = nlohmann::json::object();
        return result;
    }

    std::string agent_priv = GetEnvOrDefault("QUOODLE_AGENT_PRIVKEY_B64", "");
    if (agent_priv.empty()) {
        return BuildUnsupported("missing agent private key");
    }
    std::string sig_b64;
    try {
        sig_b64 = SignEd25519(agent_priv, canonical);
    } catch (const std::exception &ex) {
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_SIG_INVALID";
        result.error_message = ex.what();
        result.result = nlohmann::json::object();
        return result;
    }
    payload["sig"]["sig"] = sig_b64;

    nlohmann::json response;
    if (!SendRequest(payload, &response)) {
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_EXECUTION_FAILED";
        result.error_message = "Failed to reach privileged daemon";
        result.result = nlohmann::json::object();
        return result;
    }

    if (!response.is_object()) {
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_SCHEMA_INVALID";
        result.error_message = "Invalid daemon response";
        result.result = nlohmann::json::object();
        return result;
    }
    if (!response.contains("request_id") || response["request_id"] != payload["request_id"]) {
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_SCHEMA_INVALID";
        result.error_message = "Mismatched request_id";
        result.result = nlohmann::json::object();
        return result;
    }

    if (!response.contains("sig") || !response["sig"].is_object()) {
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_SIG_INVALID";
        result.error_message = "Missing response signature";
        result.result = nlohmann::json::object();
        return result;
    }

    std::string daemon_pub = GetEnvOrDefault("QUOODLE_DAEMON_PUBKEY_B64", "");
    if (daemon_pub.empty()) {
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_SIG_INVALID";
        result.error_message = "Missing daemon public key";
        result.result = nlohmann::json::object();
        return result;
    }

    std::string resp_sig = response["sig"].value("sig", "");
    nlohmann::json resp_copy = response;
    resp_copy["sig"]["sig"] = "";
    std::string resp_canonical;
    try {
        resp_canonical = CanonicalizeJcs(resp_copy.dump());
    } catch (const std::exception &ex) {
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_SCHEMA_INVALID";
        result.error_message = ex.what();
        result.result = nlohmann::json::object();
        return result;
    }
    if (!VerifyEd25519(daemon_pub, resp_canonical, resp_sig)) {
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_SIG_INVALID";
        result.error_message = "Daemon signature verification failed";
        result.result = nlohmann::json::object();
        return result;
    }

    ExecutionResult result;
    result.status = response.value("status", "error");
    result.exec_id = response.value("exec_id", "");
    result.execution_state = (result.status == "ok") ? "completed" : "failed";
    if (response.contains("error") && response["error"].is_object()) {
        result.error_type = response["error"].value("type", "");
        result.error_message = response["error"].value("message", "");
    }
    if (response.contains("result")) {
        result.result = response["result"];
    } else {
        result.result = nlohmann::json::object();
    }
    return result;
}

}  // namespace quoodle
