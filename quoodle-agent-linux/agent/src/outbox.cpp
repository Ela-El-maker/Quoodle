#include "outbox.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <cstdlib>
#include <cerrno>
#include <fstream>
#include <iostream>

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

}  // namespace

Outbox::Outbox() : state_dir_(GetEnvOrDefault("QUOODLE_AGENT_STATE_DIR", "/var/lib/quoodle/agent")) {}

bool Outbox::EnsureDir() const {
    return MkdirRecursive(state_dir_);
}

std::string Outbox::OutboxPath() const {
    return state_dir_ + "/outbox.json";
}

bool Outbox::Load() {
    if (!EnsureDir()) {
        return false;
    }
    std::ifstream in(OutboxPath());
    if (!in.good()) {
        return true;
    }
    nlohmann::json parsed;
    try {
        in >> parsed;
    } catch (const std::exception &ex) {
        std::cerr << "Failed to parse outbox: " << ex.what() << "\n";
        return false;
    }
    if (!parsed.is_array()) {
        return false;
    }
    pending_.clear();
    for (const auto &item : parsed) {
        OutboxItem entry;
        if (item.contains("type") && item["type"].is_string()) {
            entry.type = item["type"].get<std::string>();
        }
        if (item.contains("command_id") && item["command_id"].is_string()) {
            entry.command_id = item["command_id"].get<std::string>();
        }
        if (item.contains("device_id") && item["device_id"].is_string()) {
            entry.device_id = item["device_id"].get<std::string>();
        }
        if (item.contains("ack_status") && item["ack_status"].is_string()) {
            entry.ack_status = item["ack_status"].get<std::string>();
        }
        if (item.contains("ack_reason") && item["ack_reason"].is_string()) {
            entry.ack_reason = item["ack_reason"].get<std::string>();
        }
        if (item.contains("result")) {
            entry.result = ResultFromJson(item["result"]);
        }
        pending_.push_back(std::move(entry));
    }
    return true;
}

bool Outbox::Save() const {
    if (!EnsureDir()) {
        return false;
    }
    nlohmann::json out = nlohmann::json::array();
    for (const auto &item : pending_) {
        nlohmann::json entry;
        entry["type"] = item.type;
        entry["command_id"] = item.command_id;
        entry["device_id"] = item.device_id;
        entry["ack_status"] = item.ack_status;
        entry["ack_reason"] = item.ack_reason;
        entry["result"] = ResultToJson(item.result);
        out.push_back(entry);
    }
    std::string tmp_path = OutboxPath() + ".tmp";
    std::ofstream tmp(tmp_path, std::ios::trunc);
    if (!tmp.good()) {
        return false;
    }
    tmp << out.dump();
    tmp.close();
    if (!tmp.good()) {
        return false;
    }
    if (::rename(tmp_path.c_str(), OutboxPath().c_str()) != 0) {
        return false;
    }
    return true;
}

void Outbox::EnqueueAck(const std::string &command_id,
                        const std::string &device_id,
                        const std::string &status,
                        const std::string &reason) {
    OutboxItem item;
    item.type = "COMMAND_ACK";
    item.command_id = command_id;
    item.device_id = device_id;
    item.ack_status = status;
    item.ack_reason = reason;
    pending_.push_back(std::move(item));
    if (!Save()) {
        std::cerr << "Warning: failed to persist outbox ACK\n";
    }
}

void Outbox::EnqueueResult(const std::string &command_id, const std::string &device_id,
                           const ExecutionResult &result) {
    OutboxItem item;
    item.type = "COMMAND_RESULT";
    item.command_id = command_id;
    item.device_id = device_id;
    item.result = result;
    pending_.push_back(std::move(item));
    if (!Save()) {
        std::cerr << "Warning: failed to persist outbox RESULT\n";
    }
}

const OutboxItem *Outbox::Peek() const {
    if (pending_.empty()) {
        return nullptr;
    }
    return &pending_.front();
}

void Outbox::PopFront() {
    if (pending_.empty()) {
        return;
    }
    pending_.pop_front();
    if (!Save()) {
        std::cerr << "Warning: failed to persist outbox after pop\n";
    }
}

const std::deque<OutboxItem> &Outbox::Pending() const {
    return pending_;
}

}  // namespace quoodle
