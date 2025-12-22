#include "sequence_manager.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>

#ifdef _WIN32
#include <windows.h>
#endif

namespace
{

    std::string get_env(const char *name)
    {
        if (const char *v = std::getenv(name))
        {
            return std::string(v);
        }
        return {};
    }

} // namespace

std::string default_sequence_path()
{
    // Prefer explicit override.
    std::string p = get_env("AGENT_SEQ_PATH");
    if (!p.empty())
    {
        return p;
    }

#ifdef _WIN32
    // Prefer ProgramData for services.
    std::string programData = get_env("PROGRAMDATA");
    if (!programData.empty())
    {
        return programData + "\\System002\\agent_seq.dat";
    }

    // User-profile fallback.
    std::string appData = get_env("APPDATA");
    if (!appData.empty())
    {
        return appData + "\\SecureAgent\\agent_seq.dat";
    }
#endif

    // Fallback: relative data path.
    return std::string("./data/agent_seq.dat");
}

SequenceManager::SequenceManager(std::string path) : path_(std::move(path))
{
    load_from_disk();
}

std::uint64_t SequenceManager::current() const
{
    std::lock_guard<std::mutex> lock(mu_);
    return last_;
}

std::uint64_t SequenceManager::next()
{
    std::lock_guard<std::mutex> lock(mu_);
    // Strictly increasing.
    last_ = last_ + 1;
    persist_to_disk(last_);
    return last_;
}

void SequenceManager::load_from_disk()
{
    std::lock_guard<std::mutex> lock(mu_);

    try
    {
        std::ifstream in(path_, std::ios::in);
        if (!in.good())
        {
            last_ = 0;
            return;
        }
        std::string line;
        std::getline(in, line);
        if (line.empty())
        {
            last_ = 0;
            return;
        }
        std::uint64_t parsed = 0;
        {
            std::istringstream iss(line);
            iss >> parsed;
        }
        last_ = parsed;
    }
    catch (...)
    {
        last_ = 0;
    }
}

void SequenceManager::persist_to_disk(std::uint64_t value)
{
    try
    {
        std::filesystem::path p(path_);
        auto parent = p.parent_path();
        if (!parent.empty())
        {
            std::filesystem::create_directories(parent);
        }

        // Write-then-rename for best-effort atomicity.
        std::filesystem::path tmp = p;
        tmp += ".tmp";

        {
            std::ofstream out(tmp.string(), std::ios::out | std::ios::trunc);
            out << value;
            out.flush();
        }

        std::error_code ec;
        std::filesystem::rename(tmp, p, ec);
        if (ec)
        {
            // Fall back to overwrite.
            std::ofstream out(path_, std::ios::out | std::ios::trunc);
            out << value;
        }
    }
    catch (...)
    {
        // If persistence fails, we still advanced in-memory. On restart this could
        // regress, but callers can provide an explicit durable path.
    }
}
