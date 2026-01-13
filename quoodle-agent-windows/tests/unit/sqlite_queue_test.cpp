#include <cassert>
#include <chrono>
#include <cstdio>
#include <iostream>
#include <thread>

#include "../src/storage/sqlite_queue.hpp"

// Test database path (will be deleted after tests)
static const char *TEST_DB = "test_queue.db";

void cleanup_db()
{
    std::remove(TEST_DB);
    std::remove("test_queue.db-wal");
    std::remove("test_queue.db-shm");
}

void test_open_close()
{
    std::cout << "test_open_close... ";
    cleanup_db();

    SqliteQueueConfig config;
    config.db_path = TEST_DB;
    SqliteQueue queue(config);

    assert(!queue.is_open());
    assert(queue.open());
    assert(queue.is_open());
    queue.close();
    assert(!queue.is_open());

    cleanup_db();
    std::cout << "PASS\n";
}

void test_enqueue_dequeue()
{
    std::cout << "test_enqueue_dequeue... ";
    cleanup_db();

    SqliteQueueConfig config;
    config.db_path = TEST_DB;
    SqliteQueue queue(config);
    assert(queue.open());

    // Enqueue items
    assert(queue.enqueue("cmd-001", "{\"method\":\"ping\"}", QueuePriority::Normal));
    assert(queue.enqueue("cmd-002", "{\"method\":\"lock\"}", QueuePriority::High));
    assert(queue.enqueue("cmd-003", "{\"method\":\"wipe\"}", QueuePriority::Critical));

    assert(queue.pending_count() == 3);

    // Dequeue should return highest priority first
    QueueItem item;
    assert(queue.dequeue(item));
    assert(item.command_id == "cmd-003"); // Critical priority
    assert(item.priority == QueuePriority::Critical);
    queue.complete(item.id);

    assert(queue.dequeue(item));
    assert(item.command_id == "cmd-002"); // High priority
    queue.complete(item.id);

    assert(queue.dequeue(item));
    assert(item.command_id == "cmd-001"); // Normal priority
    queue.complete(item.id);

    // Queue should be empty
    assert(!queue.dequeue(item));
    assert(queue.pending_count() == 0);

    queue.close();
    cleanup_db();
    std::cout << "PASS\n";
}

void test_legacy_api()
{
    std::cout << "test_legacy_api... ";
    cleanup_db();

    SqliteQueueConfig config;
    config.db_path = TEST_DB;
    SqliteQueue queue(config);
    assert(queue.open());

    // Legacy enqueue (no payload, normal priority)
    assert(queue.enqueue("legacy-001"));
    assert(queue.enqueue("legacy-002"));

    // Legacy dequeue (returns command_id only)
    std::string cmd_id;
    assert(queue.dequeue(cmd_id));
    assert(cmd_id == "legacy-001");

    assert(queue.dequeue(cmd_id));
    assert(cmd_id == "legacy-002");

    assert(!queue.dequeue(cmd_id));

    queue.close();
    cleanup_db();
    std::cout << "PASS\n";
}

void test_duplicate_rejection()
{
    std::cout << "test_duplicate_rejection... ";
    cleanup_db();

    SqliteQueueConfig config;
    config.db_path = TEST_DB;
    SqliteQueue queue(config);
    assert(queue.open());

    assert(queue.enqueue("dup-001"));
    assert(!queue.enqueue("dup-001")); // Should fail - duplicate
    assert(queue.pending_count() == 1);

    queue.close();
    cleanup_db();
    std::cout << "PASS\n";
}

void test_retry_with_backoff()
{
    std::cout << "test_retry_with_backoff... ";
    cleanup_db();

    SqliteQueueConfig config;
    config.db_path = TEST_DB;
    config.default_max_retries = 3;
    config.retry_delay_ms = 100;
    config.retry_backoff_multiplier = 2.0;
    SqliteQueue queue(config);
    assert(queue.open());

    assert(queue.enqueue("retry-001"));

    // Dequeue and fail
    QueueItem item;
    assert(queue.dequeue(item));
    assert(item.retry_count == 0);

    // First failure - should reschedule
    assert(queue.fail(item.id, "connection error"));

    // Item should not be immediately available (scheduled for future)
    assert(queue.pending_count() == 0);

    // Wait for retry delay
    std::this_thread::sleep_for(std::chrono::milliseconds(150));
    assert(queue.pending_count() == 1);

    // Dequeue again
    assert(queue.dequeue(item));
    assert(item.retry_count == 1);
    assert(item.error_message == "connection error");

    // Second failure
    assert(queue.fail(item.id, "timeout"));
    std::this_thread::sleep_for(std::chrono::milliseconds(250));

    assert(queue.dequeue(item));
    assert(item.retry_count == 2);

    // Third failure - max retries exceeded
    assert(!queue.fail(item.id, "final error")); // Returns false - not rescheduled

    // Item should now be in Failed status
    assert(queue.count_by_status(QueueItemStatus::Failed) == 1);
    assert(queue.pending_count() == 0);

    queue.close();
    cleanup_db();
    std::cout << "PASS\n";
}

void test_cancel()
{
    std::cout << "test_cancel... ";
    cleanup_db();

    SqliteQueueConfig config;
    config.db_path = TEST_DB;
    SqliteQueue queue(config);
    assert(queue.open());

    assert(queue.enqueue("cancel-001"));
    assert(queue.enqueue("cancel-002"));
    assert(queue.pending_count() == 2);

    assert(queue.cancel("cancel-001"));
    assert(queue.pending_count() == 1);

    assert(!queue.cancel("cancel-001")); // Already cancelled
    assert(!queue.cancel("nonexistent"));

    queue.close();
    cleanup_db();
    std::cout << "PASS\n";
}

void test_crash_recovery()
{
    std::cout << "test_crash_recovery... ";
    cleanup_db();

    // Simulate crash: leave item in Processing state
    {
        SqliteQueueConfig config;
        config.db_path = TEST_DB;
        SqliteQueue queue(config);
        assert(queue.open());

        assert(queue.enqueue("crash-001"));
        assert(queue.enqueue("crash-002"));

        QueueItem item;
        assert(queue.dequeue(item)); // Now in Processing state
        assert(item.command_id == "crash-001");

        // "Crash" - close without completing
        queue.close();
    }

    // Reopen and recover
    {
        SqliteQueueConfig config;
        config.db_path = TEST_DB;
        SqliteQueue queue(config);
        assert(queue.open());

        // Item should still be in Processing
        assert(queue.count_by_status(QueueItemStatus::Processing) == 1);
        assert(queue.pending_count() == 1); // Only crash-002

        // Recover stuck items
        int recovered = queue.recover_stuck_items();
        assert(recovered == 1);

        // Now both items should be pending
        assert(queue.pending_count() == 2);

        queue.close();
    }

    cleanup_db();
    std::cout << "PASS\n";
}

void test_persistence()
{
    std::cout << "test_persistence... ";
    cleanup_db();

    // Create and populate queue
    {
        SqliteQueueConfig config;
        config.db_path = TEST_DB;
        SqliteQueue queue(config);
        assert(queue.open());

        assert(queue.enqueue("persist-001", "{\"data\":\"test1\"}"));
        assert(queue.enqueue("persist-002", "{\"data\":\"test2\"}"));
        queue.close();
    }

    // Reopen and verify data persisted
    {
        SqliteQueueConfig config;
        config.db_path = TEST_DB;
        SqliteQueue queue(config);
        assert(queue.open());

        assert(queue.pending_count() == 2);
        assert(queue.contains("persist-001"));
        assert(queue.contains("persist-002"));

        auto item = queue.get_by_command_id("persist-001");
        assert(item.has_value());
        assert(item->payload == "{\"data\":\"test1\"}");

        queue.close();
    }

    cleanup_db();
    std::cout << "PASS\n";
}

void test_purge()
{
    std::cout << "test_purge... ";
    cleanup_db();

    SqliteQueueConfig config;
    config.db_path = TEST_DB;
    SqliteQueue queue(config);
    assert(queue.open());

    // Add and complete items
    assert(queue.enqueue("purge-001"));
    assert(queue.enqueue("purge-002"));

    QueueItem item;
    assert(queue.dequeue(item));
    queue.complete(item.id);
    assert(queue.dequeue(item));
    queue.complete(item.id);

    assert(queue.count_by_status(QueueItemStatus::Completed) == 2);

    // Purge with 0 age (all completed)
    int purged = queue.purge_completed(0);
    assert(purged == 2);
    assert(queue.count_by_status(QueueItemStatus::Completed) == 0);

    queue.close();
    cleanup_db();
    std::cout << "PASS\n";
}

void test_peek()
{
    std::cout << "test_peek... ";
    cleanup_db();

    SqliteQueueConfig config;
    config.db_path = TEST_DB;
    SqliteQueue queue(config);
    assert(queue.open());

    assert(!queue.peek().has_value());

    assert(queue.enqueue("peek-001"));

    auto item = queue.peek();
    assert(item.has_value());
    assert(item->command_id == "peek-001");
    assert(item->status == QueueItemStatus::Pending);

    // Peek again - should return same item
    item = queue.peek();
    assert(item.has_value());
    assert(item->command_id == "peek-001");

    // Count unchanged
    assert(queue.pending_count() == 1);

    queue.close();
    cleanup_db();
    std::cout << "PASS\n";
}

int main()
{
    std::cout << "\n=== SQLite Queue Tests ===\n\n";

    test_open_close();
    test_enqueue_dequeue();
    test_legacy_api();
    test_duplicate_rejection();
    test_retry_with_backoff();
    test_cancel();
    test_crash_recovery();
    test_persistence();
    test_purge();
    test_peek();

    std::cout << "\n=== All tests passed! ===\n\n";
    return 0;
}
