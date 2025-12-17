#include <string>
#include <filesystem>
#include "../utils/logger.hpp"

namespace fs = std::filesystem;

bool execute_commit_update(const std::string &sandbox_id)
{
    try
    {
        fs::path stage_dir = fs::current_path() / "stage";
        if (!fs::exists(stage_dir))
        {
            utils::log_error("commit_update: stage directory missing");
            return false;
        }
        // find staged file starting with sandbox_id
        for (auto &p : fs::directory_iterator(stage_dir))
        {
            auto name = p.path().filename().string();
            if (name.rfind(sandbox_id, 0) == 0)
            {
                fs::path dest_dir = fs::current_path() / "current";
                fs::create_directories(dest_dir);
                fs::path dest = dest_dir / p.path().filename();
                fs::rename(p.path(), dest);
                utils::log_info(std::string("commit_update: moved ") + name + " to current/");
                return true;
            }
        }
        utils::log_error(std::string("commit_update: staged sandbox not found: ") + sandbox_id);
        return false;
    }
    catch (const std::exception &e)
    {
        utils::log_error(std::string("commit_update: exception: ") + e.what());
        return false;
    }
}
