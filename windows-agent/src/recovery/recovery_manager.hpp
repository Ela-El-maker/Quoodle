#pragma once

#include <string>

class RecoveryManager {
public:
    std::string last_error() const { return last_error_; }

    bool check_time_sync(int skew_seconds) {
        if (skew_seconds > 5) {
            last_error_ = "clock_skew";
            return false;
        }
        last_error_.clear();
        return true;
    }

    void mark_service_issue(const std::string& issue) {
        last_error_ = issue;
    }

    void clear() { last_error_.clear(); }

private:
    std::string last_error_;
};
