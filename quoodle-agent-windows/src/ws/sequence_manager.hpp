#pragma once

#include <cstdint>
#include <mutex>
#include <string>

class SequenceManager
{
public:
    explicit SequenceManager(std::string path);

    // Returns the next strictly-increasing sequence number and persists it.
    // Thread-safe.
    std::uint64_t next();

    // Exposed for tests/diagnostics.
    std::uint64_t current() const;

private:
    void load_from_disk();
    void persist_to_disk(std::uint64_t value);

    std::string path_;
    mutable std::mutex mu_;
    std::uint64_t last_{0};
};

// Returns default persistent sequence path.
std::string default_sequence_path();
