#include "telemetry_queue.hpp"

#include <chrono>
#include <sstream>

#include <sqlite3.h>

#include "../logging/logger.hpp"

namespace
{
const char *kCreateSql = R"(
    CREATE TABLE IF NOT EXISTS telemetry_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seq INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_ms INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        last_error TEXT DEFAULT ''
    );
    CREATE INDEX IF NOT EXISTS idx_tq_next_attempt
      ON telemetry_queue(next_attempt_ms, seq, id);
)";
} // namespace

TelemetryQueue::TelemetryQueue(const TelemetryQueueConfig &config)
    : config_(config)
{
}

TelemetryQueue::~TelemetryQueue()
{
    close();
}

bool TelemetryQueue::open()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (db_)
    {
        return true;
    }

    const int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX;
    if (sqlite3_open_v2(config_.db_path.c_str(), &db_, flags, nullptr) != SQLITE_OK)
    {
        Logger::log(LogLevel::Error, "telemetry queue open failed: " + std::string(sqlite3_errmsg(db_)));
        if (db_)
        {
            sqlite3_close(db_);
            db_ = nullptr;
        }
        return false;
    }

    sqlite3_busy_timeout(db_, config_.busy_timeout_ms);
    if (config_.enable_wal)
    {
        char *err = nullptr;
        if (sqlite3_exec(db_, "PRAGMA journal_mode=WAL;", nullptr, nullptr, &err) != SQLITE_OK)
        {
            Logger::log(LogLevel::Warn, "telemetry queue WAL enable failed: " + std::string(err ? err : "unknown"));
            sqlite3_free(err);
        }
    }

    if (!init_schema())
    {
        sqlite3_close(db_);
        db_ = nullptr;
        return false;
    }

    Logger::log(LogLevel::Info, "telemetry queue opened: " + config_.db_path);
    return true;
}

void TelemetryQueue::close()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (db_)
    {
        sqlite3_close(db_);
        db_ = nullptr;
    }
}

bool TelemetryQueue::is_open() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return db_ != nullptr;
}

bool TelemetryQueue::init_schema()
{
    char *err = nullptr;
    if (sqlite3_exec(db_, kCreateSql, nullptr, nullptr, &err) != SQLITE_OK)
    {
        Logger::log(LogLevel::Error, "telemetry queue schema init failed: " + std::string(err ? err : "unknown"));
        sqlite3_free(err);
        return false;
    }
    return true;
}

std::int64_t TelemetryQueue::now_ms() const
{
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

std::int32_t TelemetryQueue::enforce_limit_locked()
{
    if (!db_ || config_.max_items <= 0)
    {
        return 0;
    }

    std::int64_t count = 0;
    sqlite3_stmt *count_stmt = nullptr;
    if (sqlite3_prepare_v2(db_, "SELECT COUNT(*) FROM telemetry_queue", -1, &count_stmt, nullptr) != SQLITE_OK)
    {
        return 0;
    }
    if (sqlite3_step(count_stmt) == SQLITE_ROW)
    {
        count = sqlite3_column_int64(count_stmt, 0);
    }
    sqlite3_finalize(count_stmt);

    if (count < config_.max_items)
    {
        return 0;
    }

    const std::int64_t to_delete = (count - config_.max_items) + 1;
    sqlite3_stmt *del_stmt = nullptr;
    if (sqlite3_prepare_v2(
            db_,
            "DELETE FROM telemetry_queue WHERE id IN (SELECT id FROM telemetry_queue ORDER BY created_at_ms ASC, id ASC LIMIT ?)",
            -1,
            &del_stmt,
            nullptr) != SQLITE_OK)
    {
        return 0;
    }
    sqlite3_bind_int64(del_stmt, 1, to_delete);
    const int rc = sqlite3_step(del_stmt);
    sqlite3_finalize(del_stmt);
    if (rc != SQLITE_DONE)
    {
        return 0;
    }
    return static_cast<std::int32_t>(to_delete);
}

std::int32_t TelemetryQueue::enqueue(std::int64_t seq, const std::string &payload_json, const std::string &reason)
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_)
    {
        return 0;
    }

    const std::int32_t dropped = enforce_limit_locked();
    const std::int64_t now = now_ms();

    sqlite3_stmt *stmt = nullptr;
    if (sqlite3_prepare_v2(
            db_,
            "INSERT INTO telemetry_queue(seq, payload_json, retry_count, next_attempt_ms, created_at_ms, last_error) VALUES (?, ?, 0, ?, ?, ?)",
            -1,
            &stmt,
            nullptr) != SQLITE_OK)
    {
        return dropped;
    }
    sqlite3_bind_int64(stmt, 1, seq);
    sqlite3_bind_text(stmt, 2, payload_json.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 3, now);
    sqlite3_bind_int64(stmt, 4, now);
    sqlite3_bind_text(stmt, 5, reason.c_str(), -1, SQLITE_TRANSIENT);
    const int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE)
    {
        Logger::log(LogLevel::Warn, "telemetry queue enqueue failed: " + std::string(sqlite3_errmsg(db_)));
    }
    return dropped;
}

std::vector<TelemetryQueueItem> TelemetryQueue::fetch_batch(std::int32_t limit, std::int64_t now_ms_value)
{
    std::lock_guard<std::mutex> lock(mutex_);
    std::vector<TelemetryQueueItem> out;
    if (!db_)
    {
        return out;
    }

    sqlite3_stmt *stmt = nullptr;
    if (sqlite3_prepare_v2(
            db_,
            "SELECT id, seq, payload_json, retry_count, next_attempt_ms, created_at_ms, last_error "
            "FROM telemetry_queue WHERE next_attempt_ms <= ? ORDER BY seq ASC, id ASC LIMIT ?",
            -1,
            &stmt,
            nullptr) != SQLITE_OK)
    {
        return out;
    }

    sqlite3_bind_int64(stmt, 1, now_ms_value);
    sqlite3_bind_int(stmt, 2, limit);

    while (sqlite3_step(stmt) == SQLITE_ROW)
    {
        TelemetryQueueItem item;
        item.id = sqlite3_column_int64(stmt, 0);
        item.seq = sqlite3_column_int64(stmt, 1);
        const char *payload = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 2));
        const char *last_error = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 6));
        item.payload_json = payload ? payload : "";
        item.retry_count = sqlite3_column_int(stmt, 3);
        item.next_attempt_ms = sqlite3_column_int64(stmt, 4);
        item.created_at_ms = sqlite3_column_int64(stmt, 5);
        item.last_error = last_error ? last_error : "";
        out.push_back(std::move(item));
    }

    sqlite3_finalize(stmt);
    return out;
}

bool TelemetryQueue::delete_ids(const std::vector<std::int64_t> &ids)
{
    if (ids.empty())
    {
        return true;
    }

    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_)
    {
        return false;
    }

    std::ostringstream oss;
    oss << "DELETE FROM telemetry_queue WHERE id IN (";
    for (std::size_t i = 0; i < ids.size(); ++i)
    {
        if (i > 0)
        {
            oss << ',';
        }
        oss << '?';
    }
    oss << ")";

    sqlite3_stmt *stmt = nullptr;
    if (sqlite3_prepare_v2(db_, oss.str().c_str(), -1, &stmt, nullptr) != SQLITE_OK)
    {
        return false;
    }
    for (std::size_t i = 0; i < ids.size(); ++i)
    {
        sqlite3_bind_int64(stmt, static_cast<int>(i + 1), ids[i]);
    }

    const int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE;
}

bool TelemetryQueue::mark_failed(std::int64_t id, const std::string &error, std::int64_t next_attempt_ms)
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_)
    {
        return false;
    }

    sqlite3_stmt *stmt = nullptr;
    if (sqlite3_prepare_v2(
            db_,
            "UPDATE telemetry_queue SET retry_count = retry_count + 1, next_attempt_ms = ?, last_error = ? WHERE id = ?",
            -1,
            &stmt,
            nullptr) != SQLITE_OK)
    {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, next_attempt_ms);
    sqlite3_bind_text(stmt, 2, error.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 3, id);

    const int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE;
}

std::int64_t TelemetryQueue::pending_count() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_)
    {
        return 0;
    }
    sqlite3_stmt *stmt = nullptr;
    if (sqlite3_prepare_v2(db_, "SELECT COUNT(*) FROM telemetry_queue", -1, &stmt, nullptr) != SQLITE_OK)
    {
        return 0;
    }
    std::int64_t count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW)
    {
        count = sqlite3_column_int64(stmt, 0);
    }
    sqlite3_finalize(stmt);
    return count;
}

