#include <cstdlib>
#include <iostream>
#include <stdexcept>

#include "outbox.h"
#include "policy.h"
#include "privileged_client.h"
#include "replay.h"
#include "state_store.h"
#include "wss_client.h"

namespace {

std::string GetEnvOrThrow(const char *name) {
    const char *value = std::getenv(name);
    if (!value || !*value) {
        throw std::runtime_error(std::string("Missing required env var: ") + name);
    }
    return value;
}

}  // namespace

int main() {
    try {
        auto ws_url = GetEnvOrThrow("QUOODLE_WS_URL");
        auto device_id = GetEnvOrThrow("QUOODLE_DEVICE_ID");
        auto agent_jwt = GetEnvOrThrow("QUOODLE_AGENT_JWT");
        auto agent_kid = GetEnvOrThrow("QUOODLE_AGENT_KID");
        auto agent_priv_b64 = GetEnvOrThrow("QUOODLE_AGENT_PRIVKEY_B64");

        quoodle::AgentStateStore state;
        state.Load();

        quoodle::PolicyState policy;
        if (!state.PolicyHash().empty()) {
            policy.SetPolicyHash(state.PolicyHash());
        }

        quoodle::Outbox outbox;
        outbox.Load();

        quoodle::ReplayCache replay(state);
        replay.Load();

        quoodle::PrivilegedClient privileged(replay);
        quoodle::CommandProcessor processor(outbox, privileged, state);

        quoodle::WssClient client(
            ws_url, device_id, agent_jwt, agent_kid, agent_priv_b64, policy, outbox, replay, state, processor);
        client.Run();
        return 0;
    } catch (const std::exception &ex) {
        std::cerr << "Agent startup failed: " << ex.what() << "\n";
        return 1;
    }
}
