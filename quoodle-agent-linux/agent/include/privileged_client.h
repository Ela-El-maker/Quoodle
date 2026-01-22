#pragma once

#include <string>

#include <nlohmann/json.hpp>

#include "outbox.h"
#include "replay.h"

namespace quoodle {

struct CommandRequest {
    std::string command_id;
    std::string method;
    nlohmann::json params;
    std::string policy_hash;
};

class PrivilegedClient {
public:
    explicit PrivilegedClient(ReplayCache &replay);

    ExecutionResult Execute(const CommandRequest &request);

private:
    std::string MapMethodToCapability(const std::string &method) const;
    ExecutionResult BuildUnsupported(const std::string &method) const;

    bool SendRequest(const nlohmann::json &payload, nlohmann::json *response) const;
    std::string BuildRequestId() const;
    std::string IsoTimestamp() const;

    ReplayCache &replay_;
};

}  // namespace quoodle
