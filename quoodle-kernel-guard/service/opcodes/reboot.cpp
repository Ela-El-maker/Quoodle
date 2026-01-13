// reboot.cpp
#include <string>
#include <windows.h>
#include "../utils/logger.hpp"

bool execute_reboot(int delay_seconds)
{
    // For safety, require env var to allow dangerous operations in dev/staging.
    const char *allow = std::getenv("ALLOW_DANGEROUS_OPS");
    if (!allow || std::string(allow) != "1")
    {
        utils::log_info("reboot: dry-run (ALLOW_DANGEROUS_OPS not set)");
        return true;
    }

    std::string msg =
        "Reboot by KernelService (delay=" + std::to_string(delay_seconds) + "s)";
    utils::log_info("reboot: requesting system reboot: " + msg);

    // Copy into a mutable buffer because InitiateSystemShutdownExA takes LPSTR
    char buf[256];
    strncpy_s(buf, msg.c_str(), sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';

    BOOL ok = InitiateSystemShutdownExA(
        nullptr,
        buf, // LPSTR (char*)
        delay_seconds,
        TRUE,
        TRUE,
        SHTDN_REASON_MAJOR_SOFTWARE);

    if (!ok)
    {
        DWORD err = GetLastError();
        utils::log_error("reboot: InitiateSystemShutdownExA failed, error=" +
                         std::to_string(err));
    }

    return ok != 0;
}

