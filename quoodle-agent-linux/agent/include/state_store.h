#pragma once

#include <string>

namespace quoodle {

class AgentStateStore {
public:
    AgentStateStore();

    bool Load();
    bool Save() const;

    long NextSequence();
    long CurrentSequence() const;

    void SetPolicyHash(const std::string &policy_hash);
    std::string PolicyHash() const;

    void SetLastDeliveryId(const std::string &delivery_id);
    std::string LastDeliveryId() const;

private:
    bool EnsureDir() const;
    std::string StateFilePath() const;

    std::string state_dir_;
    long sequence_{0};
    std::string policy_hash_;
    std::string last_delivery_id_;
};

}  // namespace quoodle
