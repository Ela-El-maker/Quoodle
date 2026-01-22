#pragma once

#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace quoodle {

struct ExecutionResult {
    std::string execution_state;
    std::string status;
    std::string exec_id;
    std::string error_type;
    std::string error_message;
    nlohmann::json result;
};

struct OutboxItem {
    std::string type;
    std::string command_id;
    std::string device_id;
    ExecutionResult result;
};

class Outbox {
public:
    Outbox();

    bool Load();
    bool Save() const;

    void EnqueueAck(const std::string &command_id, const std::string &device_id);
    void EnqueueResult(const std::string &command_id, const std::string &device_id, const ExecutionResult &result);

    std::vector<OutboxItem> Drain();
    const std::vector<OutboxItem> &Pending() const;

private:
    bool EnsureDir() const;
    std::string OutboxPath() const;

    std::string state_dir_;
    std::vector<OutboxItem> pending_;
};

}  // namespace quoodle
