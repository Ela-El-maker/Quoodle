#include "command_processor.h"

namespace quoodle {

CommandProcessor::CommandProcessor(Outbox &outbox, PrivilegedClient &privileged, AgentStateStore &state)
    : outbox_(outbox), privileged_(privileged), state_(state) {}

ExecutionResult CommandProcessor::Handle(const CommandEnvelope &command) {
    if (!command.delivery_id.empty()) {
        state_.SetLastDeliveryId(command.delivery_id);
    }
    if (command.requires_ack) {
        outbox_.EnqueueAck(command.command_id, command.device_id);
    }

    CommandRequest request;
    request.command_id = command.command_id;
    request.method = command.method;
    request.params = command.params;
    request.policy_hash = command.policy_hash;

    ExecutionResult result = privileged_.Execute(request);
    outbox_.EnqueueResult(command.command_id, command.device_id, result);
    return result;
}

}  // namespace quoodle
