#pragma once

#include <string>

class AgentState {
public:
    explicit AgentState(std::string device_id)
        : device_id_(std::move(device_id)) {}

    const std::string& device_id() const { return device_id_; }
    const std::string& session_id() const { return session_id_; }
    void set_session_id(const std::string& session_id) { session_id_ = session_id; }

    const std::string& policy_hash() const { return policy_hash_; }
    void set_policy_hash(const std::string& hash) { policy_hash_ = hash; }

    bool quarantined() const { return quarantined_; }
    const std::string& quarantine_reason() const { return quarantine_reason_; }
    void quarantine(const std::string& reason) { quarantined_ = true; quarantine_reason_ = reason; }
    void clear_quarantine() { quarantined_ = false; quarantine_reason_.clear(); }

    void set_release(const std::string& release_id) { last_release_id_ = release_id; }
    const std::string& last_release_id() const { return last_release_id_; }

private:
    std::string device_id_;
    std::string session_id_;
    std::string policy_hash_;
    bool quarantined_{false};
    std::string quarantine_reason_;
    std::string last_release_id_;
};
