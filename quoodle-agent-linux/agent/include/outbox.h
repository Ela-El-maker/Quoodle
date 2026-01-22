#pragma once

#include <string>
#include <deque>

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
    std::string ack_status;
    std::string ack_reason;
    ExecutionResult result;
};

class Outbox {
public:
    Outbox();

    bool Load();
    bool Save() const;

    void EnqueueAck(const std::string &command_id,
                    const std::string &device_id,
                    const std::string &status = "received",
                    const std::string &reason = "");
    void EnqueueResult(const std::string &command_id, const std::string &device_id, const ExecutionResult &result);

    const OutboxItem *Peek() const;
    void PopFront();
    const std::deque<OutboxItem> &Pending() const;

private:
    bool EnsureDir() const;
    std::string OutboxPath() const;

    std::string state_dir_;
    std::deque<OutboxItem> pending_;
};

}  // namespace quoodle
