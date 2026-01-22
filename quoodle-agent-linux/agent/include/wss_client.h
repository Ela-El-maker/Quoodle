#pragma once

#include <ctime>
#include <string>

#include <openssl/ssl.h>
#include <nlohmann/json.hpp>

#include "command_processor.h"
#include "outbox.h"
#include "policy.h"
#include "replay.h"
#include "state_store.h"

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
              AgentStateStore &state,
              CommandProcessor &processor);

    void Run();

private:
    bool SendSigned(const nlohmann::json &payload);
    bool SendAuth();
    bool VerifyControllerSig(const nlohmann::json &msg) const;
    bool VerifyEnvelopeSig(const nlohmann::json &env) const;
    bool HandleAuthAck(const nlohmann::json &msg);
    bool HandlePolicyUpdate(const nlohmann::json &msg);
    bool HandleCommandDelivery(const nlohmann::json &msg);
    bool HandleUpdateAnnounce(const nlohmann::json &msg);
    bool FlushOutbox();
    bool SendHeartbeat();
    bool SendTelemetry();
    bool ProcessInbound(const std::string &payload);
    bool InitTls(const std::string &host);
    void CloseTransport();

    std::string ws_url_;
    std::string device_id_;
    std::string agent_jwt_;
    std::string agent_kid_;
    std::string agent_priv_b64_;
    PolicyState &policy_;
    Outbox &outbox_;
    ReplayCache &replay_;
    AgentStateStore &state_;
    CommandProcessor &processor_;
    std::string session_id_;
    int heartbeat_interval_{30};
    int telemetry_interval_{60};
    long last_controller_seq_{0};
    int socket_fd_{-1};
    bool authenticated_{false};
    std::time_t start_time_{0};
    std::time_t last_heartbeat_{0};
    std::time_t last_telemetry_{0};
    uint64_t last_cpu_total_{0};
    uint64_t last_cpu_idle_{0};
    uint64_t last_net_rx_{0};
    uint64_t last_net_tx_{0};
    bool has_cpu_sample_{false};
    bool has_net_sample_{false};
    bool use_tls_{false};
    SSL_CTX *tls_ctx_{nullptr};
    SSL *tls_{nullptr};
};

}  // namespace quoodle
