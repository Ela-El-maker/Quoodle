#include <string>
#include <filesystem>
#include <system_error>
#include "../utils/logger.hpp"

namespace fs = std::filesystem;

bool execute_commit_update(const std::string& sandbox_id)
{
    // 1. Safety Gate
    const char *allow = std::getenv("ALLOW_DANGEROUS_OPS");
    if (!allow || std::string(allow) != "1")
    {
        utils::log_info("commit_update: dry-run (sandbox_id=" + sandbox_id + ")");
        return true;
    }

    try
    {
        fs::path stage_root = fs::current_path() / "stage" / "sandbox";
        
        // 2. Early Exit if directory missing
        if (!fs::exists(stage_root)) {
            utils::log_error("commit_update: stage directory missing: " + stage_root.string());
            return false;
        }

        fs::path staged_pkg;
        for (const auto& entry : fs::directory_iterator(stage_root))
        {
            if (entry.path().stem().string() == sandbox_id)
            {
                staged_pkg = entry.path();
                break;
            }
        }

        if (staged_pkg.empty() || !fs::exists(staged_pkg))
        {
            utils::log_error("commit_update: package not found for ID: " + sandbox_id);
            return false;
        }

        fs::path active_pkg = fs::current_path() / staged_pkg.filename();
        std::error_code ec;

        // 3. Handle Overwrite (Critical for Windows)
        if (fs::exists(active_pkg)) {
            fs::path backup = active_pkg.string() + ".bak";
            fs::rename(active_pkg, backup, ec); // Move existing to backup
            if (ec) {
                utils::log_error("commit_update: failed to move existing package to backup: " + ec.message());
                return false;
            }
        }

        // 4. Perform Atomic Move
        utils::log_info("commit_update: committing " + staged_pkg.filename().string());
        fs::rename(staged_pkg, active_pkg, ec);

        if (ec) {
            utils::log_error("commit_update: rename failed: " + ec.message());
            return false;
        }

        utils::log_info("commit_update: SUCCESS sandbox_id=" + sandbox_id);
        return true;
    }
    catch (const fs::filesystem_error &e)
    {
        utils::log_error("commit_update: filesystem exception: " + std::string(e.what()));
        return false;
    }
    catch (const std::exception &e)
    {
        utils::log_error("commit_update: generic exception: " + std::string(e.what()));
        return false;
    }
}
