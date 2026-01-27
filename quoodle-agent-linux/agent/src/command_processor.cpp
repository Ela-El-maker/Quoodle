#include "command_processor.h"

#include <cstdlib>
#include <cstring>

namespace {

bool EnvFlagEnabled(const char *name) {
    const char *value = std::getenv(name);
    if (!value || !*value) {
        return false;
    }
    return std::strcmp(value, "1") == 0 ||
           std::strcmp(value, "true") == 0 ||
           std::strcmp(value, "yes") == 0;
}

}  // namespace

namespace quoodle {

CommandProcessor::CommandProcessor(Outbox &outbox, PrivilegedClient &privileged, AgentStateStore &state)
    : outbox_(outbox), privileged_(privileged), state_(state) {}

ExecutionResult CommandProcessor::Handle(const CommandEnvelope &command) {
    if (!command.delivery_id.empty()) {
        state_.SetLastDeliveryId(command.delivery_id);
    }
    bool out_of_order = EnvFlagEnabled("QUOODLE_FAULT_OUT_OF_ORDER_RESULT");
    if (command.requires_ack && !out_of_order) {
        outbox_.EnqueueAck(command.command_id, command.device_id, "received", "");
    }

    CommandRequest request;
    request.command_id = command.command_id;
    request.method = command.method;
    request.params = command.params;
    if (command.method == "enable_input") {
        request.params["enabled"] = true;
    } else if (command.method == "disable_input") {
        request.params["enabled"] = false;
    }
    request.policy_hash = command.policy_hash;

    ExecutionResult result = privileged_.Execute(request);

    outbox_.EnqueueResult(command.command_id, command.device_id, result);
    if (command.requires_ack && out_of_order) {
        outbox_.EnqueueAck(command.command_id, command.device_id, "received", "");
    }
    ProcessedCommand processed;
    processed.command_id = command.command_id;
    processed.requires_ack = command.requires_ack;
    if (command.requires_ack) {
        processed.ack_status = "received";
        processed.ack_reason = "";
    }
    processed.result = result;
    state_.RememberCommand(processed);
    return result;
}

}  // namespace quoodle
