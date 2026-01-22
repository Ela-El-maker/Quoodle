#pragma once

#include <string>
#include <unordered_map>

namespace quoodle {

class PolicyState {
public:
    void Apply(const std::unordered_map<std::string, std::string> &policy_fields);
    void SetPolicyHash(const std::string &policy_hash);
    std::unordered_map<std::string, std::string> AgentInfo() const;
    std::string HwidHash() const;
    std::string PolicyHash() const;

private:
    std::string policy_hash_;
    std::string policy_version_;
};

}  // namespace quoodle
