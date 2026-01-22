#include "wss_client.h"

#include <iostream>

namespace quoodle {

WssClient::WssClient(std::string ws_url,
                     std::string device_id,
                     std::string agent_jwt,
                     std::string agent_kid,
                     std::string agent_priv_b64,
                     PolicyState &policy,
                     Outbox &outbox,
                     ReplayCache &replay,
                     PrivilegedClient &privileged)
    : ws_url_(std::move(ws_url)),
      device_id_(std::move(device_id)),
      agent_jwt_(std::move(agent_jwt)),
      agent_kid_(std::move(agent_kid)),
      agent_priv_b64_(std::move(agent_priv_b64)),
      policy_(policy),
      outbox_(outbox),
      replay_(replay),
      privileged_(privileged) {}

void WssClient::Run() {
    std::cout << "WSS client skeleton started for device_id=" << device_id_ << "\n";
    std::cout << "TODO: Implement WSS AUTH, message loop, and signature checks.\n";
}

}  // namespace quoodle
