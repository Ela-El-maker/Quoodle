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

}  // namespace quoodle
