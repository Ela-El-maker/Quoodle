#pragma once

#include <string>

#include "outbox.h"
#include "policy.h"
#include "privileged_client.h"
#include "replay.h"

namespace quoodle {

class WssClient {
public:
    WssClient(std::string ws_url,
              std::string device_id,
              std::string agent_jwt,
              std::string agent_kid,
              std::string agent_priv_b64,
              PolicyState &policy,
              Outbox &outbox,
              ReplayCache &replay,
              PrivilegedClient &privileged);

    void Run();

private:
    std::string ws_url_;
    std::string device_id_;
    std::string agent_jwt_;
    std::string agent_kid_;
    std::string agent_priv_b64_;
    PolicyState &policy_;
    Outbox &outbox_;
    ReplayCache &replay_;
    PrivilegedClient &privileged_;
};

}  // namespace quoodle
