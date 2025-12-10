#include "sqlite_queue.hpp"

bool SqliteQueue::enqueue(const std::string& command_id) {
    commands_.push_back(command_id);
    return true;
}

bool SqliteQueue::dequeue(std::string& command_id) {
    if (commands_.empty()) return false;
    command_id = commands_.front();
    commands_.erase(commands_.begin());
    return true;
}
