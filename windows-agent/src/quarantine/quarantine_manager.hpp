#pragma once

#include <string>
#include <unordered_set>

class QuarantineManager {
public:
    bool is_quarantined() const { return quarantined_; }
    const std::string& reason() const { return reason_; }

    void enter(const std::string& reason) {
        quarantined_ = true;
        reason_ = reason;
    }

    void exit() {
        quarantined_ = false;
        reason_.clear();
    }

    bool is_allowed(const std::string& method) const {
        if (!quarantined_) return true;
        return allowlist_.count(method) > 0;
    }

private:
    bool quarantined_{false};
    std::string reason_;
    const std::unordered_set<std::string> allowlist_{"time_sync", "fetch_revocations", "reauth", "collect_diagnostics", "ping"};
};
