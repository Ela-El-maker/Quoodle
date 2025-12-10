#pragma once

#include <string>
#include <vector>

class SqliteQueue {
public:
    bool enqueue(const std::string& command_id);
    bool dequeue(std::string& command_id);

private:
    std::vector<std::string> commands_;
};
