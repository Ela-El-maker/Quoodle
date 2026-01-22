#include "policy.h"

namespace quoodle {

void PolicyState::Apply(const std::unordered_map<std::string, std::string> &policy_fields) {
    auto it_hash = policy_fields.find("policy_hash");
    if (it_hash != policy_fields.end()) {
        policy_hash_ = it_hash->second;
    }
    auto it_version = policy_fields.find("policy_version");
    if (it_version != policy_fields.end()) {
        policy_version_ = it_version->second;
    }
}

void PolicyState::SetPolicyHash(const std::string &policy_hash) {
    policy_hash_ = policy_hash;
}

std::unordered_map<std::string, std::string> PolicyState::AgentInfo() const {
    return {
        {"agent_version", "0.1.0-linux"},
        {"os_build", "linux"},
    };
}

std::string PolicyState::HwidHash() const {
    return "sha256:placeholder";
}

std::string PolicyState::PolicyHash() const {
    return policy_hash_;
}

}  // namespace quoodle
