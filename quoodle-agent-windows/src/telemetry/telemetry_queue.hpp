#pragma once

#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

struct sqlite3;

struct TelemetryQueueConfig
{
    std::string db_path{"C:/ProgramData/Quoodle/telemetry_queue.db"};
    std::int32_t max_items{5000};
    std::int32_t busy_timeout_ms{5000};
    bool enable_wal{true};
};

struct TelemetryQueueItem
{
    std::int64_t id{0};
    std::int64_t seq{0};
    std::string payload_json;
    std::int32_t retry_count{0};
    std::int64_t next_attempt_ms{0};
    std::int64_t created_at_ms{0};
    std::string last_error;
};

class TelemetryQueue
{
public:
    explicit TelemetryQueue(const TelemetryQueueConfig &config = {});
    ~TelemetryQueue();

    TelemetryQueue(const TelemetryQueue &) = delete;
    TelemetryQueue &operator=(const TelemetryQueue &) = delete;

    bool open();
    void close();
    bool is_open() const;

    std::int32_t enqueue(std::int64_t seq, const std::string &payload_json, const std::string &reason = "");
    std::vector<TelemetryQueueItem> fetch_batch(std::int32_t limit, std::int64_t now_ms);
    bool delete_ids(const std::vector<std::int64_t> &ids);
    bool mark_failed(std::int64_t id, const std::string &error, std::int64_t next_attempt_ms);
    std::int64_t pending_count() const;

private:
    TelemetryQueueConfig config_;
    sqlite3 *db_{nullptr};
    mutable std::mutex mutex_;

    bool init_schema();
    std::int64_t now_ms() const;
    std::int32_t enforce_limit_locked();
};

