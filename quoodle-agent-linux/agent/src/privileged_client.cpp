#include "privileged_client.h"

#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <chrono>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <iostream>
#include <random>
#include <unordered_map>
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

bool ReadFull(int fd, void *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t r = read(fd, static_cast<char *>(buf) + off, len - off);
        if (r == 0) {
            return false;
        }
        if (r < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        off += static_cast<size_t>(r);
    }
    return true;
}

bool ReadFrame(int fd, std::string *payload) {
    uint32_t net_len = 0;
    if (!ReadFull(fd, &net_len, sizeof(net_len))) {
        return false;
    }
    uint32_t len = ntohl(net_len);
    if (len == 0 || len > 1024 * 1024) {
        return false;
    }
    std::string buf(len, '\0');
    if (!ReadFull(fd, buf.data(), len)) {
        return false;
    }
    *payload = std::move(buf);
    return true;
}

bool WriteFull(int fd, const void *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t w = write(fd, static_cast<const char *>(buf) + off, len - off);
        if (w < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        off += static_cast<size_t>(w);
    }
    return true;
}

bool WriteFrame(int fd, const std::string &payload) {
    uint32_t net_len = htonl(static_cast<uint32_t>(payload.size()));
    if (!WriteFull(fd, &net_len, sizeof(net_len))) {
        return false;
    }
    if (payload.empty()) {
        return true;
    }
    return WriteFull(fd, payload.data(), payload.size());
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
    static const std::unordered_map<std::string, std::string> kMap = {
        {"lock_screen", "CAP_LOCK_SESSION"},
        {"logout_user", "CAP_LOGOUT_SESSION"},
        {"logout", "CAP_LOGOUT_SESSION"},
        {"reboot_device", "CAP_REBOOT_SYSTEM"},
        {"reboot_system", "CAP_REBOOT_SYSTEM"},
        {"reboot", "CAP_REBOOT_SYSTEM"},
        {"shutdown_device", "CAP_SHUTDOWN_SYSTEM"},
        {"shutdown", "CAP_SHUTDOWN_SYSTEM"},
        {"disable_input", "CAP_INPUT_CONTROL"},
        {"enable_input", "CAP_INPUT_CONTROL"},
        {"set_wallpaper", "CAP_SET_WALLPAPER"},
        {"show_message", "CAP_SHOW_MESSAGE"},
        {"lock_and_capture", "CAP_LOCK_AND_CAPTURE"},
        {"ping", "CAP_HEALTH_CHECK"},
        {"sysinfo", "CAP_SYSINFO"},
        {"collect_system_info", "CAP_SYSINFO"},
        {"list_processes", "CAP_LIST_PROCESSES"},
        {"get_process_list", "CAP_LIST_PROCESSES"},
        {"get_users", "CAP_GET_USERS"},
        {"get_sessions", "CAP_GET_SESSIONS"},
        {"list_sessions", "CAP_GET_SESSIONS"},
        {"list_services", "CAP_LIST_SERVICES"},
        {"network_info", "CAP_NETWORK_INFO"},
        {"netinfo", "CAP_NETWORK_INFO"},
        {"list_mounts", "CAP_LIST_MOUNTS"},
        {"get_env_fingerprint", "CAP_ENV_FINGERPRINT"},
        {"list_files", "CAP_FS_LIST"},
        {"stat_file", "CAP_FS_STAT"},
        {"read_file", "CAP_FS_READ"},
        {"search_files", "CAP_FS_SEARCH"},
        {"hash_file", "CAP_FS_HASH"},
        {"download_file", "CAP_FS_DOWNLOAD"},
        {"upload_file", "CAP_FS_UPLOAD"},
        {"delete_file", "CAP_FS_DELETE"},
        {"move_file", "CAP_FS_MOVE"},
        {"screenshot", "CAP_SCREENSHOT"},
        {"get_active_window", "CAP_ACTIVE_WINDOW"},
        {"get_idle_time", "CAP_IDLE_TIME"},
        {"kill_process", "CAP_TERMINATE_PROCESS"},
        {"pause_process", "CAP_PAUSE_PROCESS"},
        {"resume_process", "CAP_RESUME_PROCESS"},
        {"start_service", "CAP_SERVICE_START"},
        {"stop_service", "CAP_SERVICE_STOP"},
        {"restart_service", "CAP_SERVICE_RESTART"},
        {"disconnect_network", "CAP_NETWORK_DISCONNECT"},
        {"reconnect_network", "CAP_NETWORK_RECONNECT"},
        {"list_connections", "CAP_LIST_CONNECTIONS"},
        {"block_outbound", "CAP_BLOCK_OUTBOUND"},
        {"allow_outbound", "CAP_ALLOW_OUTBOUND"},
        {"rotate_agent_keys", "CAP_ROTATE_AGENT_KEYS"},
        {"rotate_keys", "CAP_ROTATE_AGENT_KEYS"},
        {"revoke_device", "CAP_REVOKE_DEVICE"},
        {"force_repair", "CAP_FORCE_REPAIR"},
        {"invalidate_sessions", "CAP_INVALIDATE_SESSIONS"},
        {"re_attest", "CAP_ATTEST"},
        {"attest_device", "CAP_ATTEST"},
        {"attest", "CAP_ATTEST"},
        {"fail_attestation", "CAP_FAIL_ATTESTATION"},
        {"enter_quarantine", "CAP_ENTER_QUARANTINE"},
        {"exit_quarantine", "CAP_EXIT_QUARANTINE"},
        {"quarantine", "CAP_NETWORK_ISOLATION"},
        {"policy_probe", "CAP_POLICY_PROBE"},
        {"get_command_log", "CAP_GET_COMMAND_LOG"},
        {"get_audit_trail", "CAP_GET_AUDIT_TRAIL"},
        {"export_artifacts", "CAP_EXPORT_ARTIFACTS"},
        {"verify_signature", "CAP_VERIFY_SIGNATURE"},
        {"replay_request", "CAP_REPLAY_REQUEST"},
        {"panic_disable_agent", "CAP_PANIC_DISABLE_AGENT"},
        {"revoke_all_keys", "CAP_REVOKE_ALL_KEYS"},
        {"restore_defaults", "CAP_RESTORE_DEFAULTS"},
        {"unlock_all", "CAP_UNLOCK_ALL"},
        {"health_check", "CAP_HEALTH_CHECK"},
        {"collect_logs", "CAP_COLLECT_LOGS"},
        {"update_agent", "CAP_UPDATE_AGENT"},
    };

    auto it = kMap.find(method);
    if (it != kMap.end()) {
        return it->second;
    }
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
        std::cerr << "PrivilegedClient: socket() failed: " << std::strerror(errno) << "\n";
        return false;
    }
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", socket_path.c_str());
    if (connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) != 0) {
        std::cerr << "PrivilegedClient: connect() failed: " << std::strerror(errno) << "\n";
        close(fd);
        return false;
    }
    std::string payload_text = payload.dump();
    if (!WriteFrame(fd, payload_text)) {
        std::cerr << "PrivilegedClient: write failed\n";
        close(fd);
        return false;
    }
    std::string response_text;
    if (!ReadFrame(fd, &response_text)) {
        std::cerr << "PrivilegedClient: read failed\n";
        close(fd);
        return false;
    }
    close(fd);
    try {
        *response = nlohmann::json::parse(response_text);
    } catch (const std::exception &) {
        std::cerr << "PrivilegedClient: response parse failed\n";
        return false;
    }
    return true;
}

ExecutionResult PrivilegedClient::Execute(const CommandRequest &request) {
    try {
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
        std::cerr << "PrivilegedClient: request failed\n";
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_EXECUTION_FAILED";
        result.error_message = "Failed to reach privileged daemon";
        result.result = nlohmann::json::object();
        return result;
    }

    try {
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

        std::string resp_sig;
        if (response["sig"].contains("sig") && response["sig"]["sig"].is_string()) {
            resp_sig = response["sig"]["sig"].get<std::string>();
        }
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
        result.status = "error";
        if (response.contains("status") && response["status"].is_string()) {
            result.status = response["status"].get<std::string>();
        }
        if (response.contains("exec_id") && response["exec_id"].is_string()) {
            result.exec_id = response["exec_id"].get<std::string>();
        }
        result.execution_state = (result.status == "ok") ? "completed" : "failed";
        if (response.contains("error") && response["error"].is_object()) {
            if (response["error"].contains("type") && response["error"]["type"].is_string()) {
                result.error_type = response["error"]["type"].get<std::string>();
            }
            if (response["error"].contains("message") && response["error"]["message"].is_string()) {
                result.error_message = response["error"]["message"].get<std::string>();
            }
        }
        if (response.contains("result")) {
            result.result = response["result"];
        } else {
            result.result = nlohmann::json::object();
        }
        return result;
    } catch (const std::exception &ex) {
        std::cerr << "PrivilegedClient: response handling failed: " << ex.what() << "\n";
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_EXECUTION_FAILED";
        result.error_message = ex.what();
        result.result = nlohmann::json::object();
        return result;
    }
    } catch (const std::exception &ex) {
        std::cerr << "PrivilegedClient: execute failed: " << ex.what() << "\n";
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_EXECUTION_FAILED";
        result.error_message = ex.what();
        result.result = nlohmann::json::object();
        return result;
    }
}

}  // namespace quoodle
