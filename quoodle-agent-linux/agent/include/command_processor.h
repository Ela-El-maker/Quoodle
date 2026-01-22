#pragma once

#include <string>

#include <nlohmann/json.hpp>

#include "outbox.h"
#include "privileged_client.h"
#include "state_store.h"

namespace quoodle {

struct CommandEnvelope {
    std::string command_id;
    std::string method;
    nlohmann::json params;
    bool requires_ack{true};
    std::string device_id;
    std::string delivery_id;
    std::string policy_hash;
};

class CommandProcessor {
public:
    CommandProcessor(Outbox &outbox, PrivilegedClient &privileged, AgentStateStore &state);

    ExecutionResult Handle(const CommandEnvelope &command);

private:
    Outbox &outbox_;
    PrivilegedClient &privileged_;
    AgentStateStore &state_;
};

}  // namespace quoodle
