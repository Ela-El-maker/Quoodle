#include <string>
#include <filesystem>
#include <system_error>
#include "../utils/logger.hpp"

namespace fs = std::filesystem;

bool execute_rollback_update(const std::string& snapshot_id)
{
    const char *allow = std::getenv("ALLOW_DANGEROUS_OPS");
    if (!allow || std::string(allow) != "1")
    {
        utils::log_info("rollback_update: dry-run (snapshot_id=" + snapshot_id + ")");
        return true;
    }

    try
    {
        std::error_code ec;
        fs::path active_dir = fs::current_path();
        fs::path snapshot_root = active_dir / "snapshots";

        if (!fs::exists(snapshot_root)) {
            utils::log_error("rollback_update: snapshots directory missing");
            return false;
        }

        fs::path snapshot_pkg;
        for (const auto& entry : fs::directory_iterator(snapshot_root))
        {
            if (entry.path().stem().string() == snapshot_id)
            {
                snapshot_pkg = fs::weakly_canonical(entry.path());
                break;
            }
        }

        if (snapshot_pkg.empty() || !fs::exists(snapshot_pkg))
        {
            utils::log_error("rollback_update: snapshot not found for ID: " + snapshot_id);
            return false;
        }

        fs::path active_pkg = active_dir / snapshot_pkg.filename();
        fs::path backup_active = active_dir / ("rollback_backup_" + snapshot_pkg.filename().string());

        // 1. Prevent rollback to the same physical file (Refinement 2)
        if (fs::exists(active_pkg) && fs::equivalent(snapshot_pkg, active_pkg, ec))
        {
            utils::log_error("rollback_update: snapshot is equivalent to active package; skipping");
            return false;
        }

        // 2. Handle Stale Backup Protection
        if (fs::exists(backup_active)) {
            fs::remove_all(backup_active, ec);
        }

        // 3. Create Safety Backup
        if (fs::exists(active_pkg))
        {
            utils::log_info("rollback_update: backing up active state");
            fs::rename(active_pkg, backup_active, ec);
            if (ec) {
                utils::log_error("rollback_update: backup failed: " + ec.message());
                return false;
            }
        }

        // 4. Restore from Snapshot (Refinement 3: Recursive Copy for future-proofing)
        utils::log_info("rollback_update: restoring " + snapshot_pkg.filename().string());
        
        

        fs::copy(snapshot_pkg, active_pkg, 
                fs::copy_options::recursive | fs::copy_options::overwrite_existing, ec);

        if (ec)
        {
            utils::log_error("rollback_update: restore failed: " + ec.message());
            if (fs::exists(backup_active)) {
                fs::rename(backup_active, active_pkg, ec);
            }
            return false;
        }

        // 5. Verify restore target before deleting backup (Refinement 1)
        if (fs::exists(active_pkg)) 
        {
            // Optional: Add checksum verification here for maximum safety
            if (fs::exists(backup_active)) {
                fs::remove_all(backup_active, ec);
            }
            utils::log_info("rollback_update: SUCCESS snapshot_id=" + snapshot_id);
            return true;
        }
        else 
        {
            utils::log_error("rollback_update: active package missing post-restore");
            return false;
        }
    }
    catch (const std::exception &e)
    {
        utils::log_error("rollback_update: fatal exception: " + std::string(e.what()));
        return false;
    }
}
