#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

// Forward declare sqlite3 to avoid exposing it in the header
struct sqlite3;
struct sqlite3_stmt;

/**
 * Priority levels for queued items.
 */
enum class QueuePriority : int
{
    Low = 0,
    Normal = 1,
    High = 2,
    Critical = 3
};

/**
 * Status of a queued item.
 */
enum class QueueItemStatus : int
{
    Pending = 0,    // Waiting to be processed
    Processing = 1, // Currently being processed
    Completed = 2,  // Successfully processed
    Failed = 3,     // Failed after max retries
    Cancelled = 4   // Manually cancelled
};

/**
 * A queued command item with metadata.
 */
struct QueueItem
{
    std::int64_t id{0};     // SQLite rowid
    std::string command_id; // Unique command identifier
    std::string payload;    // JSON payload
    QueuePriority priority{QueuePriority::Normal};
    QueueItemStatus status{QueueItemStatus::Pending};
    std::int32_t retry_count{0};  // Number of attempts
    std::int32_t max_retries{3};  // Max allowed retries
    std::int64_t created_at{0};   // Unix timestamp (ms)
    std::int64_t updated_at{0};   // Unix timestamp (ms)
    std::int64_t scheduled_at{0}; // When to process (for delayed retry)
    std::string error_message;    // Last error if failed
};

/**
 * Configuration for the SQLite queue.
 */
struct SqliteQueueConfig
{
    std::string db_path{"agent_queue.db"};  // Database file path
    std::int32_t default_max_retries{3};    // Default max retries per item
    std::int64_t retry_delay_ms{1000};      // Initial retry delay
    double retry_backoff_multiplier{2.0};   // Exponential backoff multiplier
    std::int64_t max_retry_delay_ms{60000}; // Max retry delay
    bool enable_wal{true};                  // Enable WAL mode for better concurrency
    std::int32_t busy_timeout_ms{5000};     // SQLite busy timeout
};

/**
 * Persistent command queue backed by SQLite.
 *
 * Features:
 * - FIFO with priority support (higher priority dequeued first)
 * - Crash-safe persistence
 * - Automatic retry with exponential backoff
 * - Thread-safe operations
 * - Transaction support for batch operations
 */
class SqliteQueue
{
public:
    explicit SqliteQueue(const SqliteQueueConfig &config = {});
    ~SqliteQueue();

    // Non-copyable, non-movable (due to sqlite3* and mutex)
    SqliteQueue(const SqliteQueue &) = delete;
    SqliteQueue &operator=(const SqliteQueue &) = delete;
    SqliteQueue(SqliteQueue &&) = delete;
    SqliteQueue &operator=(SqliteQueue &&) = delete;

    /**
     * Open the database and initialize schema.
     * @return true on success
     */
    bool open();

    /**
     * Close the database connection.
     */
    void close();

    /**
     * Check if database is open.
     */
    bool is_open() const;

    // =========================================================================
    // Queue Operations
    // =========================================================================

    /**
     * Add a command to the queue.
     * @param command_id Unique command identifier
     * @param payload JSON payload to store
     * @param priority Queue priority
     * @return true on success
     */
    bool enqueue(const std::string &command_id,
                 const std::string &payload = "",
                 QueuePriority priority = QueuePriority::Normal);

    /**
     * Legacy enqueue for backward compatibility.
     */
    bool enqueue(const std::string &command_id);

    /**
     * Get and remove the next pending item (highest priority, oldest first).
     * Marks item as Processing.
     * @param item Output item if found
     * @return true if item was dequeued
     */
    bool dequeue(QueueItem &item);

    /**
     * Legacy dequeue for backward compatibility.
     */
    bool dequeue(std::string &command_id);

    /**
     * Peek at the next item without removing it.
     * @return Item if available, nullopt otherwise
     */
    std::optional<QueueItem> peek() const;

    /**
     * Mark an item as completed (removes from active queue).
     * @param id Item ID
     * @return true on success
     */
    bool complete(std::int64_t id);

    /**
     * Mark an item as failed and schedule retry if retries remaining.
     * @param id Item ID
     * @param error_message Error description
     * @return true if item was rescheduled, false if max retries exceeded
     */
    bool fail(std::int64_t id, const std::string &error_message = "");

    /**
     * Cancel a pending item.
     * @param command_id Command ID to cancel
     * @return true if item was found and cancelled
     */
    bool cancel(const std::string &command_id);

    /**
     * Requeue items stuck in Processing state (crash recovery).
     * Call this on startup.
     * @return Number of items requeued
     */
    std::int32_t recover_stuck_items();

    // =========================================================================
    // Query Operations
    // =========================================================================

    /**
     * Get count of pending items.
     */
    std::int64_t pending_count() const;

    /**
     * Get count of items by status.
     */
    std::int64_t count_by_status(QueueItemStatus status) const;

    /**
     * Check if a command is already queued.
     */
    bool contains(const std::string &command_id) const;

    /**
     * Get item by command ID.
     */
    std::optional<QueueItem> get_by_command_id(const std::string &command_id) const;

    /**
     * Get all failed items.
     */
    std::vector<QueueItem> get_failed_items() const;

    // =========================================================================
    // Maintenance
    // =========================================================================

    /**
     * Remove completed items older than specified age.
     * @param max_age_ms Maximum age in milliseconds
     * @return Number of items purged
     */
    std::int32_t purge_completed(std::int64_t max_age_ms = 86400000); // 24h default

    /**
     * Compact the database (VACUUM).
     */
    bool compact();

private:
    SqliteQueueConfig config_;
    sqlite3 *db_{nullptr};
    mutable std::mutex mutex_;

    // Prepared statements for performance
    sqlite3_stmt *stmt_enqueue_{nullptr};
    sqlite3_stmt *stmt_dequeue_{nullptr};
    sqlite3_stmt *stmt_complete_{nullptr};
    sqlite3_stmt *stmt_fail_{nullptr};
    sqlite3_stmt *stmt_count_pending_{nullptr};

    bool init_schema();
    bool prepare_statements();
    void finalize_statements();
    std::int64_t current_time_ms() const;
    std::int64_t calculate_retry_delay(std::int32_t retry_count) const;
    std::optional<QueueItem> row_to_item(sqlite3_stmt *stmt) const;
};
