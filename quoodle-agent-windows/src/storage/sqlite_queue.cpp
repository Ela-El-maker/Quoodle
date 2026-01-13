#include "sqlite_queue.hpp"

#include <chrono>
#include <cstring>
#include <sqlite3.h>

#include "../logging/logger.hpp"

// SQL statements
static const char *SQL_CREATE_TABLE = R"(
    CREATE TABLE IF NOT EXISTS command_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        command_id TEXT UNIQUE NOT NULL,
        payload TEXT DEFAULT '',
        priority INTEGER DEFAULT 1,
        status INTEGER DEFAULT 0,
        retry_count INTEGER DEFAULT 0,
        max_retries INTEGER DEFAULT 3,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        scheduled_at INTEGER NOT NULL,
        error_message TEXT DEFAULT ''
    );
    CREATE INDEX IF NOT EXISTS idx_queue_status_priority_scheduled 
        ON command_queue(status, priority DESC, scheduled_at ASC);
    CREATE INDEX IF NOT EXISTS idx_queue_command_id ON command_queue(command_id);
)";

static const char *SQL_ENQUEUE = R"(
    INSERT INTO command_queue 
        (command_id, payload, priority, status, retry_count, max_retries, 
         created_at, updated_at, scheduled_at, error_message)
    VALUES (?, ?, ?, 0, 0, ?, ?, ?, ?, '')
)";

static const char *SQL_DEQUEUE = R"(
    UPDATE command_queue 
    SET status = 1, updated_at = ?
    WHERE id = (
        SELECT id FROM command_queue 
        WHERE status = 0 AND scheduled_at <= ?
        ORDER BY priority DESC, scheduled_at ASC
        LIMIT 1
    )
    RETURNING id, command_id, payload, priority, status, retry_count, 
              max_retries, created_at, updated_at, scheduled_at, error_message
)";

static const char *SQL_COMPLETE = R"(
    UPDATE command_queue SET status = 2, updated_at = ? WHERE id = ?
)";

static const char *SQL_FAIL = R"(
    UPDATE command_queue 
    SET status = ?, retry_count = retry_count + 1, updated_at = ?, 
        scheduled_at = ?, error_message = ?
    WHERE id = ?
)";

static const char *SQL_COUNT_PENDING = R"(
    SELECT COUNT(*) FROM command_queue WHERE status = 0 AND scheduled_at <= ?
)";

SqliteQueue::SqliteQueue(const SqliteQueueConfig &config)
    : config_(config)
{
}

SqliteQueue::~SqliteQueue()
{
    close();
}

bool SqliteQueue::open()
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (db_)
    {
        return true; // Already open
    }

    int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX;
    int rc = sqlite3_open_v2(config_.db_path.c_str(), &db_, flags, nullptr);
    if (rc != SQLITE_OK)
    {
        Logger::log(LogLevel::Error, "Failed to open database: " +
                                         std::string(sqlite3_errmsg(db_)));
        sqlite3_close(db_);
        db_ = nullptr;
        return false;
    }

    // Set busy timeout
    sqlite3_busy_timeout(db_, config_.busy_timeout_ms);

    // Enable WAL mode for better concurrency
    if (config_.enable_wal)
    {
        char *err = nullptr;
        rc = sqlite3_exec(db_, "PRAGMA journal_mode=WAL;", nullptr, nullptr, &err);
        if (rc != SQLITE_OK)
        {
            Logger::log(LogLevel::Warn, "Failed to enable WAL mode: " +
                                            std::string(err ? err : "unknown"));
            sqlite3_free(err);
        }
    }

    // Initialize schema
    if (!init_schema())
    {
        sqlite3_close(db_);
        db_ = nullptr;
        return false;
    }

    // Prepare statements
    if (!prepare_statements())
    {
        sqlite3_close(db_);
        db_ = nullptr;
        return false;
    }

    Logger::log(LogLevel::Info, "SQLite queue opened: " + config_.db_path);
    return true;
}

void SqliteQueue::close()
{
    std::lock_guard<std::mutex> lock(mutex_);

    finalize_statements();

    if (db_)
    {
        sqlite3_close(db_);
        db_ = nullptr;
        Logger::log(LogLevel::Info, "SQLite queue closed");
    }
}

bool SqliteQueue::is_open() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return db_ != nullptr;
}

bool SqliteQueue::init_schema()
{
    char *err = nullptr;
    int rc = sqlite3_exec(db_, SQL_CREATE_TABLE, nullptr, nullptr, &err);
    if (rc != SQLITE_OK)
    {
        Logger::log(LogLevel::Error, "Failed to create schema: " +
                                         std::string(err ? err : "unknown"));
        sqlite3_free(err);
        return false;
    }
    return true;
}

bool SqliteQueue::prepare_statements()
{
    int rc;

    rc = sqlite3_prepare_v2(db_, SQL_ENQUEUE, -1, &stmt_enqueue_, nullptr);
    if (rc != SQLITE_OK)
    {
        Logger::log(LogLevel::Error, "Failed to prepare enqueue: " +
                                         std::string(sqlite3_errmsg(db_)));
        return false;
    }

    rc = sqlite3_prepare_v2(db_, SQL_DEQUEUE, -1, &stmt_dequeue_, nullptr);
    if (rc != SQLITE_OK)
    {
        Logger::log(LogLevel::Error, "Failed to prepare dequeue: " +
                                         std::string(sqlite3_errmsg(db_)));
        return false;
    }

    rc = sqlite3_prepare_v2(db_, SQL_COMPLETE, -1, &stmt_complete_, nullptr);
    if (rc != SQLITE_OK)
    {
        Logger::log(LogLevel::Error, "Failed to prepare complete: " +
                                         std::string(sqlite3_errmsg(db_)));
        return false;
    }

    rc = sqlite3_prepare_v2(db_, SQL_FAIL, -1, &stmt_fail_, nullptr);
    if (rc != SQLITE_OK)
    {
        Logger::log(LogLevel::Error, "Failed to prepare fail: " +
                                         std::string(sqlite3_errmsg(db_)));
        return false;
    }

    rc = sqlite3_prepare_v2(db_, SQL_COUNT_PENDING, -1, &stmt_count_pending_, nullptr);
    if (rc != SQLITE_OK)
    {
        Logger::log(LogLevel::Error, "Failed to prepare count_pending: " +
                                         std::string(sqlite3_errmsg(db_)));
        return false;
    }

    return true;
}

void SqliteQueue::finalize_statements()
{
    if (stmt_enqueue_)
    {
        sqlite3_finalize(stmt_enqueue_);
        stmt_enqueue_ = nullptr;
    }
    if (stmt_dequeue_)
    {
        sqlite3_finalize(stmt_dequeue_);
        stmt_dequeue_ = nullptr;
    }
    if (stmt_complete_)
    {
        sqlite3_finalize(stmt_complete_);
        stmt_complete_ = nullptr;
    }
    if (stmt_fail_)
    {
        sqlite3_finalize(stmt_fail_);
        stmt_fail_ = nullptr;
    }
    if (stmt_count_pending_)
    {
        sqlite3_finalize(stmt_count_pending_);
        stmt_count_pending_ = nullptr;
    }
}

std::int64_t SqliteQueue::current_time_ms() const
{
    using namespace std::chrono;
    return duration_cast<milliseconds>(
               system_clock::now().time_since_epoch())
        .count();
}

std::int64_t SqliteQueue::calculate_retry_delay(std::int32_t retry_count) const
{
    double delay = config_.retry_delay_ms;
    for (int i = 0; i < retry_count; ++i)
    {
        delay *= config_.retry_backoff_multiplier;
    }
    return std::min(static_cast<std::int64_t>(delay), config_.max_retry_delay_ms);
}

std::optional<QueueItem> SqliteQueue::row_to_item(sqlite3_stmt *stmt) const
{
    QueueItem item;
    item.id = sqlite3_column_int64(stmt, 0);
    item.command_id = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 1));
    item.payload = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 2));
    item.priority = static_cast<QueuePriority>(sqlite3_column_int(stmt, 3));
    item.status = static_cast<QueueItemStatus>(sqlite3_column_int(stmt, 4));
    item.retry_count = sqlite3_column_int(stmt, 5);
    item.max_retries = sqlite3_column_int(stmt, 6);
    item.created_at = sqlite3_column_int64(stmt, 7);
    item.updated_at = sqlite3_column_int64(stmt, 8);
    item.scheduled_at = sqlite3_column_int64(stmt, 9);
    const char *err_msg = reinterpret_cast<const char *>(sqlite3_column_text(stmt, 10));
    item.error_message = err_msg ? err_msg : "";
    return item;
}

bool SqliteQueue::enqueue(const std::string &command_id,
                          const std::string &payload,
                          QueuePriority priority)
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        Logger::log(LogLevel::Error, "Queue not open");
        return false;
    }

    sqlite3_reset(stmt_enqueue_);
    sqlite3_clear_bindings(stmt_enqueue_);

    auto now = current_time_ms();

    sqlite3_bind_text(stmt_enqueue_, 1, command_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt_enqueue_, 2, payload.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt_enqueue_, 3, static_cast<int>(priority));
    sqlite3_bind_int(stmt_enqueue_, 4, config_.default_max_retries);
    sqlite3_bind_int64(stmt_enqueue_, 5, now); // created_at
    sqlite3_bind_int64(stmt_enqueue_, 6, now); // updated_at
    sqlite3_bind_int64(stmt_enqueue_, 7, now); // scheduled_at

    int rc = sqlite3_step(stmt_enqueue_);
    if (rc != SQLITE_DONE)
    {
        if (rc == SQLITE_CONSTRAINT)
        {
            Logger::log(LogLevel::Warn, "Command already queued: " + command_id);
        }
        else
        {
            Logger::log(LogLevel::Error, "Failed to enqueue: " +
                                             std::string(sqlite3_errmsg(db_)));
        }
        return false;
    }

    Logger::log(LogLevel::Debug, "Enqueued command: " + command_id);
    return true;
}

bool SqliteQueue::enqueue(const std::string &command_id)
{
    return enqueue(command_id, "", QueuePriority::Normal);
}

bool SqliteQueue::dequeue(QueueItem &item)
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        return false;
    }

    sqlite3_reset(stmt_dequeue_);
    sqlite3_clear_bindings(stmt_dequeue_);

    auto now = current_time_ms();
    sqlite3_bind_int64(stmt_dequeue_, 1, now); // updated_at
    sqlite3_bind_int64(stmt_dequeue_, 2, now); // scheduled_at threshold

    int rc = sqlite3_step(stmt_dequeue_);
    if (rc == SQLITE_ROW)
    {
        auto result = row_to_item(stmt_dequeue_);
        if (result)
        {
            item = *result;
            Logger::log(LogLevel::Debug, "Dequeued command: " + item.command_id);
            return true;
        }
    }
    else if (rc != SQLITE_DONE)
    {
        Logger::log(LogLevel::Error, "Dequeue failed: " +
                                         std::string(sqlite3_errmsg(db_)));
    }

    return false;
}

bool SqliteQueue::dequeue(std::string &command_id)
{
    QueueItem item;
    if (dequeue(item))
    {
        command_id = item.command_id;
        // Auto-complete for legacy API
        complete(item.id);
        return true;
    }
    return false;
}

std::optional<QueueItem> SqliteQueue::peek() const
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        return std::nullopt;
    }

    const char *sql = R"(
        SELECT id, command_id, payload, priority, status, retry_count, 
               max_retries, created_at, updated_at, scheduled_at, error_message
        FROM command_queue 
        WHERE status = 0 AND scheduled_at <= ?
        ORDER BY priority DESC, scheduled_at ASC
        LIMIT 1
    )";

    sqlite3_stmt *stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK)
    {
        return std::nullopt;
    }

    sqlite3_bind_int64(stmt, 1, current_time_ms());

    std::optional<QueueItem> result;
    if (sqlite3_step(stmt) == SQLITE_ROW)
    {
        result = row_to_item(stmt);
    }

    sqlite3_finalize(stmt);
    return result;
}

bool SqliteQueue::complete(std::int64_t id)
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        return false;
    }

    sqlite3_reset(stmt_complete_);
    sqlite3_clear_bindings(stmt_complete_);

    sqlite3_bind_int64(stmt_complete_, 1, current_time_ms());
    sqlite3_bind_int64(stmt_complete_, 2, id);

    int rc = sqlite3_step(stmt_complete_);
    if (rc != SQLITE_DONE)
    {
        Logger::log(LogLevel::Error, "Failed to complete item: " +
                                         std::string(sqlite3_errmsg(db_)));
        return false;
    }

    return sqlite3_changes(db_) > 0;
}

bool SqliteQueue::fail(std::int64_t id, const std::string &error_message)
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        return false;
    }

    // First get current retry count
    const char *get_sql = "SELECT retry_count, max_retries FROM command_queue WHERE id = ?";
    sqlite3_stmt *get_stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, get_sql, -1, &get_stmt, nullptr);
    if (rc != SQLITE_OK)
    {
        return false;
    }

    sqlite3_bind_int64(get_stmt, 1, id);

    int retry_count = 0;
    int max_retries = config_.default_max_retries;

    if (sqlite3_step(get_stmt) == SQLITE_ROW)
    {
        retry_count = sqlite3_column_int(get_stmt, 0);
        max_retries = sqlite3_column_int(get_stmt, 1);
    }
    sqlite3_finalize(get_stmt);

    auto now = current_time_ms();
    QueueItemStatus new_status;
    std::int64_t scheduled_at;

    if (retry_count + 1 >= max_retries)
    {
        // Max retries exceeded - mark as failed
        new_status = QueueItemStatus::Failed;
        scheduled_at = now;
        Logger::log(LogLevel::Warn, "Command failed after max retries (id=" +
                                        std::to_string(id) + "): " + error_message);
    }
    else
    {
        // Schedule retry with backoff
        new_status = QueueItemStatus::Pending;
        scheduled_at = now + calculate_retry_delay(retry_count + 1);
        Logger::log(LogLevel::Debug, "Scheduling retry for command id=" +
                                         std::to_string(id) + " at " + std::to_string(scheduled_at));
    }

    sqlite3_reset(stmt_fail_);
    sqlite3_clear_bindings(stmt_fail_);

    sqlite3_bind_int(stmt_fail_, 1, static_cast<int>(new_status));
    sqlite3_bind_int64(stmt_fail_, 2, now);
    sqlite3_bind_int64(stmt_fail_, 3, scheduled_at);
    sqlite3_bind_text(stmt_fail_, 4, error_message.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt_fail_, 5, id);

    rc = sqlite3_step(stmt_fail_);
    if (rc != SQLITE_DONE)
    {
        Logger::log(LogLevel::Error, "Failed to update item status: " +
                                         std::string(sqlite3_errmsg(db_)));
        return false;
    }

    return new_status == QueueItemStatus::Pending; // true if rescheduled
}

bool SqliteQueue::cancel(const std::string &command_id)
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        return false;
    }

    const char *sql = "UPDATE command_queue SET status = 4, updated_at = ? WHERE command_id = ? AND status IN (0, 1)";
    sqlite3_stmt *stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK)
    {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, current_time_ms());
    sqlite3_bind_text(stmt, 2, command_id.c_str(), -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    bool success = rc == SQLITE_DONE && sqlite3_changes(db_) > 0;
    sqlite3_finalize(stmt);

    if (success)
    {
        Logger::log(LogLevel::Info, "Cancelled command: " + command_id);
    }

    return success;
}

std::int32_t SqliteQueue::recover_stuck_items()
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        return 0;
    }

    // Reset items stuck in Processing state back to Pending
    const char *sql = R"(
        UPDATE command_queue 
        SET status = 0, updated_at = ?, scheduled_at = ?
        WHERE status = 1
    )";

    sqlite3_stmt *stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK)
    {
        return 0;
    }

    auto now = current_time_ms();
    sqlite3_bind_int64(stmt, 1, now);
    sqlite3_bind_int64(stmt, 2, now);

    rc = sqlite3_step(stmt);
    int changes = sqlite3_changes(db_);
    sqlite3_finalize(stmt);

    if (changes > 0)
    {
        Logger::log(LogLevel::Info, "Recovered " + std::to_string(changes) +
                                        " stuck items");
    }

    return changes;
}

std::int64_t SqliteQueue::pending_count() const
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        return 0;
    }

    sqlite3_reset(stmt_count_pending_);
    sqlite3_clear_bindings(stmt_count_pending_);
    sqlite3_bind_int64(stmt_count_pending_, 1, current_time_ms());

    std::int64_t count = 0;
    if (sqlite3_step(stmt_count_pending_) == SQLITE_ROW)
    {
        count = sqlite3_column_int64(stmt_count_pending_, 0);
    }

    return count;
}

std::int64_t SqliteQueue::count_by_status(QueueItemStatus status) const
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        return 0;
    }

    const char *sql = "SELECT COUNT(*) FROM command_queue WHERE status = ?";
    sqlite3_stmt *stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK)
    {
        return 0;
    }

    sqlite3_bind_int(stmt, 1, static_cast<int>(status));

    std::int64_t count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW)
    {
        count = sqlite3_column_int64(stmt, 0);
    }

    sqlite3_finalize(stmt);
    return count;
}

bool SqliteQueue::contains(const std::string &command_id) const
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        return false;
    }

    const char *sql = "SELECT 1 FROM command_queue WHERE command_id = ? AND status IN (0, 1) LIMIT 1";
    sqlite3_stmt *stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK)
    {
        return false;
    }

    sqlite3_bind_text(stmt, 1, command_id.c_str(), -1, SQLITE_TRANSIENT);

    bool exists = sqlite3_step(stmt) == SQLITE_ROW;
    sqlite3_finalize(stmt);

    return exists;
}

std::optional<QueueItem> SqliteQueue::get_by_command_id(const std::string &command_id) const
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        return std::nullopt;
    }

    const char *sql = R"(
        SELECT id, command_id, payload, priority, status, retry_count, 
               max_retries, created_at, updated_at, scheduled_at, error_message
        FROM command_queue WHERE command_id = ?
    )";

    sqlite3_stmt *stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK)
    {
        return std::nullopt;
    }

    sqlite3_bind_text(stmt, 1, command_id.c_str(), -1, SQLITE_TRANSIENT);

    std::optional<QueueItem> result;
    if (sqlite3_step(stmt) == SQLITE_ROW)
    {
        result = row_to_item(stmt);
    }

    sqlite3_finalize(stmt);
    return result;
}

std::vector<QueueItem> SqliteQueue::get_failed_items() const
{
    std::lock_guard<std::mutex> lock(mutex_);

    std::vector<QueueItem> items;

    if (!db_)
    {
        return items;
    }

    const char *sql = R"(
        SELECT id, command_id, payload, priority, status, retry_count, 
               max_retries, created_at, updated_at, scheduled_at, error_message
        FROM command_queue WHERE status = 3
        ORDER BY updated_at DESC
    )";

    sqlite3_stmt *stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK)
    {
        return items;
    }

    while (sqlite3_step(stmt) == SQLITE_ROW)
    {
        auto item = row_to_item(stmt);
        if (item)
        {
            items.push_back(*item);
        }
    }

    sqlite3_finalize(stmt);
    return items;
}

std::int32_t SqliteQueue::purge_completed(std::int64_t max_age_ms)
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        return 0;
    }

    const char *sql = "DELETE FROM command_queue WHERE status = 2 AND updated_at < ?";
    sqlite3_stmt *stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK)
    {
        return 0;
    }

    sqlite3_bind_int64(stmt, 1, current_time_ms() - max_age_ms);

    rc = sqlite3_step(stmt);
    int changes = sqlite3_changes(db_);
    sqlite3_finalize(stmt);

    if (changes > 0)
    {
        Logger::log(LogLevel::Debug, "Purged " + std::to_string(changes) +
                                         " completed items");
    }

    return changes;
}

bool SqliteQueue::compact()
{
    std::lock_guard<std::mutex> lock(mutex_);

    if (!db_)
    {
        return false;
    }

    char *err = nullptr;
    int rc = sqlite3_exec(db_, "VACUUM;", nullptr, nullptr, &err);
    if (rc != SQLITE_OK)
    {
        Logger::log(LogLevel::Error, "VACUUM failed: " +
                                         std::string(err ? err : "unknown"));
        sqlite3_free(err);
        return false;
    }

    Logger::log(LogLevel::Info, "Database compacted");
    return true;
}
