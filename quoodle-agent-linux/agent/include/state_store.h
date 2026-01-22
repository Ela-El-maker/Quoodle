#pragma once

#include <string>
#include <vector>

#include "outbox.h"

namespace quoodle {

struct ProcessedCommand {
    std::string command_id;
    bool requires_ack{true};
    std::string ack_status;
    std::string ack_reason;
    ExecutionResult result;
};

class AgentStateStore {
public:
    AgentStateStore();

    bool Load();
    bool Save() const;

    long NextSequence();
    long CurrentSequence() const;

    void SetPolicyHash(const std::string &policy_hash);
    std::string PolicyHash() const;

    void SetLastDeliveryId(const std::string &delivery_id);
    std::string LastDeliveryId() const;

    bool GetProcessedCommand(const std::string &command_id, ProcessedCommand *out) const;
    void RememberCommand(const ProcessedCommand &command);

private:
    bool EnsureDir() const;
    std::string StateFilePath() const;

    std::string state_dir_;
    long sequence_{0};
    std::string policy_hash_;
    std::string last_delivery_id_;
    std::vector<ProcessedCommand> processed_commands_;
};

}  // namespace quoodle
