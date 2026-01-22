#include "state_store.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <cstdlib>
#include <cerrno>
#include <fstream>
#include <iostream>

#include <nlohmann/json.hpp>

namespace quoodle {
namespace {

constexpr size_t k_max_processed_commands = 256;

std::string GetEnvOrDefault(const char *name, const char *fallback) {
    const char *value = std::getenv(name);
    if (value && *value) {
        return value;
    }
    return fallback;
}

bool MkdirRecursive(const std::string &path) {
    if (path.empty()) {
        return false;
    }
    char tmp[4096];
    if (path.size() >= sizeof(tmp)) {
        return false;
    }
    std::snprintf(tmp, sizeof(tmp), "%s", path.c_str());
    for (char *p = tmp + 1; *p; ++p) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, 0750) != 0 && errno != EEXIST) {
                return false;
            }
            *p = '/';
        }
    }
    if (mkdir(tmp, 0750) != 0 && errno != EEXIST) {
        return false;
    }
    return true;
}

ExecutionResult ResultFromJson(const nlohmann::json &src) {
    ExecutionResult result;
    if (src.contains("execution_state") && src["execution_state"].is_string()) {
        result.execution_state = src["execution_state"].get<std::string>();
    }
    if (src.contains("status") && src["status"].is_string()) {
        result.status = src["status"].get<std::string>();
    }
    if (src.contains("exec_id") && src["exec_id"].is_string()) {
        result.exec_id = src["exec_id"].get<std::string>();
    }
    if (src.contains("error_type") && src["error_type"].is_string()) {
        result.error_type = src["error_type"].get<std::string>();
    }
    if (src.contains("error_message") && src["error_message"].is_string()) {
        result.error_message = src["error_message"].get<std::string>();
    }
    if (src.contains("result")) {
        result.result = src["result"];
    }
    return result;
}

nlohmann::json ResultToJson(const ExecutionResult &result) {
    nlohmann::json out;
    out["execution_state"] = result.execution_state;
    out["status"] = result.status;
    out["exec_id"] = result.exec_id;
    out["error_type"] = result.error_type;
    out["error_message"] = result.error_message;
    out["result"] = result.result;
    return out;
}

}  // namespace

AgentStateStore::AgentStateStore()
    : state_dir_(GetEnvOrDefault("QUOODLE_AGENT_STATE_DIR", "/var/lib/quoodle/agent")) {}

bool AgentStateStore::EnsureDir() const {
    return MkdirRecursive(state_dir_);
}

std::string AgentStateStore::StateFilePath() const {
    return state_dir_ + "/state.json";
}

bool AgentStateStore::Load() {
    if (!EnsureDir()) {
        return false;
    }
    std::ifstream in(StateFilePath());
    if (!in.good()) {
        return true;
    }
    nlohmann::json parsed;
    try {
        in >> parsed;
    } catch (const std::exception &ex) {
        std::cerr << "Failed to parse state: " << ex.what() << "\n";
        return false;
    }
    if (parsed.contains("sequence") && parsed["sequence"].is_number_integer()) {
        sequence_ = parsed["sequence"].get<long>();
    }
    if (parsed.contains("policy_hash") && parsed["policy_hash"].is_string()) {
        policy_hash_ = parsed["policy_hash"].get<std::string>();
    }
    if (parsed.contains("last_delivery_id") && parsed["last_delivery_id"].is_string()) {
        last_delivery_id_ = parsed["last_delivery_id"].get<std::string>();
    }
    processed_commands_.clear();
    if (parsed.contains("processed_commands") && parsed["processed_commands"].is_array()) {
        for (const auto &entry : parsed["processed_commands"]) {
            if (!entry.is_object()) {
                continue;
            }
            ProcessedCommand item;
            if (entry.contains("command_id") && entry["command_id"].is_string()) {
                item.command_id = entry["command_id"].get<std::string>();
            }
            if (entry.contains("requires_ack") && entry["requires_ack"].is_boolean()) {
                item.requires_ack = entry["requires_ack"].get<bool>();
            }
            if (entry.contains("ack_status") && entry["ack_status"].is_string()) {
                item.ack_status = entry["ack_status"].get<std::string>();
            }
            if (entry.contains("ack_reason") && entry["ack_reason"].is_string()) {
                item.ack_reason = entry["ack_reason"].get<std::string>();
            }
            if (entry.contains("result") && entry["result"].is_object()) {
                item.result = ResultFromJson(entry["result"]);
            }
            if (!item.command_id.empty()) {
                processed_commands_.push_back(std::move(item));
            }
        }
        if (processed_commands_.size() > k_max_processed_commands) {
            processed_commands_.erase(processed_commands_.begin(),
                                      processed_commands_.end() - k_max_processed_commands);
        }
    }
    return true;
}

bool AgentStateStore::Save() const {
    if (!EnsureDir()) {
        return false;
    }
    nlohmann::json out;
    out["sequence"] = sequence_;
    out["policy_hash"] = policy_hash_;
    out["last_delivery_id"] = last_delivery_id_;
    nlohmann::json processed = nlohmann::json::array();
    for (const auto &item : processed_commands_) {
        nlohmann::json entry;
        entry["command_id"] = item.command_id;
        entry["requires_ack"] = item.requires_ack;
        entry["ack_status"] = item.ack_status;
        entry["ack_reason"] = item.ack_reason;
        entry["result"] = ResultToJson(item.result);
        processed.push_back(entry);
    }
    out["processed_commands"] = processed;

    std::string tmp_path = StateFilePath() + ".tmp";
    std::ofstream tmp(tmp_path, std::ios::trunc);
    if (!tmp.good()) {
        return false;
    }
    tmp << out.dump();
    tmp.close();
    if (!tmp.good()) {
        return false;
    }
    if (::rename(tmp_path.c_str(), StateFilePath().c_str()) != 0) {
        return false;
    }
    return true;
}

long AgentStateStore::NextSequence() {
    sequence_ += 1;
    if (!Save()) {
        std::cerr << "Warning: failed to persist agent sequence\n";
    }
    return sequence_;
}

long AgentStateStore::CurrentSequence() const {
    return sequence_;
}

void AgentStateStore::SetPolicyHash(const std::string &policy_hash) {
    policy_hash_ = policy_hash;
    if (!Save()) {
        std::cerr << "Warning: failed to persist policy hash\n";
    }
}

std::string AgentStateStore::PolicyHash() const {
    return policy_hash_;
}

void AgentStateStore::SetLastDeliveryId(const std::string &delivery_id) {
    last_delivery_id_ = delivery_id;
    if (!Save()) {
        std::cerr << "Warning: failed to persist last delivery id\n";
    }
}

std::string AgentStateStore::LastDeliveryId() const {
    return last_delivery_id_;
}

bool AgentStateStore::GetProcessedCommand(const std::string &command_id, ProcessedCommand *out) const {
    if (command_id.empty()) {
        return false;
    }
    for (const auto &item : processed_commands_) {
        if (item.command_id == command_id) {
            if (out) {
                *out = item;
            }
            return true;
        }
    }
    return false;
}

void AgentStateStore::RememberCommand(const ProcessedCommand &command) {
    if (command.command_id.empty()) {
        return;
    }
    for (auto &item : processed_commands_) {
        if (item.command_id == command.command_id) {
            item = command;
            if (!Save()) {
                std::cerr << "Warning: failed to persist processed commands\n";
            }
            return;
        }
    }
    processed_commands_.push_back(command);
    if (processed_commands_.size() > k_max_processed_commands) {
        processed_commands_.erase(processed_commands_.begin(),
                                  processed_commands_.begin() + (processed_commands_.size() - k_max_processed_commands));
    }
    if (!Save()) {
        std::cerr << "Warning: failed to persist processed commands\n";
    }
}

}  // namespace quoodle
