#include <string>
#include <windows.h>
#include "../utils/logger.hpp"

bool execute_logout()
{
    // For safety require env var to allow dangerous operations in dev.
    const char *allow = std::getenv("ALLOW_DANGEROUS_OPS");
    if (!allow || std::string(allow) != "1")
    {
        utils::log_info("logout: dry-run (ALLOW_DANGEROUS_OPS not set)");
        return true;
    }
    BOOL ok = ExitWindowsEx(EWX_LOGOFF, 0);
    if (!ok)
        utils::log_error("logout: ExitWindowsEx failed");
    return ok != 0;
}
