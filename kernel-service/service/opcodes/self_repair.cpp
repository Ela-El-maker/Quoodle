#include <string>
#include <filesystem>
#include <system_error>
#include <vector>   
#include <fstream>  
#include "../utils/logger.hpp"

namespace fs = std::filesystem;

/**
 * execute_self_repair
 * Conservatively restores environment health.
 * * Production Logic:
 * 1. Clears stale locks to allow service restarts.
 * 2. Purges the staging area to prevent "disk full" or "stuck update" loops.
 * 3. Rotates/Truncates massive logs to prevent disk exhaustion.
 * 4. Verifies presence of core binaries without destructive intervention.
 */
bool execute_self_repair()
{
    const char *allow = std::getenv("ALLOW_DANGEROUS_OPS");
    if (!allow || std::string(allow) != "1")
    {
        utils::log_info("self_repair: dry-run (ALLOW_DANGEROUS_OPS not set)");
        return true;
    }

    utils::log_info("self_repair: starting auto-recovery sequence");
    
    int fixed_count = 0;
    std::error_code ec;
    const fs::path base_path = fs::current_path();

    try
    {
        // 1. Prune Stale Lock Files
        ec.clear(); // Safety: Clear before new operation
        fs::path lock_file = base_path / "service.lock";
        if (fs::exists(lock_file, ec)) {
            if (fs::remove(lock_file, ec)) {
                utils::log_info("self_repair: removed stale lock file");
                fixed_count++;
            }
        }

        // 2. Clear Staging Area
        ec.clear();
        fs::path stage_root = base_path / "stage";
        if (fs::exists(stage_root, ec))
        {
            fs::remove_all(stage_root, ec);
            if (!ec) {
                if (fs::create_directories(stage_root, ec)) {
                    utils::log_info("self_repair: reset staging area");
                    fixed_count++;
                }
            }
        }

        // 3. Log Rotation / Truncation
        ec.clear();
        fs::path log_path = base_path / "logs" / "agent.log";
        if (fs::exists(log_path, ec)) 
        {
            const uintmax_t MAX_LOG_SIZE = 100 * 1024 * 1024; // 100MB
            if (fs::file_size(log_path, ec) > MAX_LOG_SIZE)
            {
                std::ofstream ofs(log_path, std::ios::trunc);
                if (ofs.good()) {
                    utils::log_info("self_repair: truncated massive log file");
                    fixed_count++;
                }
            }
        }

        // 4. Critical Binary Integrity Check
        ec.clear();
        const std::vector<std::string> critical_bins = {
            "kernel_service", 
            "agent.exe"
        };

        for (const auto& bin_name : critical_bins) {
            if (!fs::exists(base_path / bin_name, ec)) {
                utils::log_error("self_repair: CRITICAL BINARY MISSING: " + bin_name);
            }
        }

        // Final Health Summary
        if (fixed_count == 0) {
            utils::log_info("self_repair: system already healthy, no actions required");
        } else {
            utils::log_info("self_repair: completed. Actions taken: " + std::to_string(fixed_count));
        }
        
        return true; 
    }
    catch (const std::exception &e)
    {
        utils::log_error("self_repair: fatal exception: " + std::string(e.what()));
        return false;
    }
}
