#include <windows.h>
#include <string>
#include "../utils/logger.hpp"

bool execute_lock_screen()
{
    // Attempt to lock the workstation. Returns true on success.
    BOOL ok = LockWorkStation();
    if (ok)
    {
        utils::log_info("lock_screen: LockWorkStation succeeded");
        return true;
    }
    else
    {
        DWORD err = GetLastError();
        utils::log_error(std::string("lock_screen: LockWorkStation failed: ") + std::to_string(err));
        return false;
    }
}
