#include "lock_screen.hpp"
#include <string>
#include <windows.h>
#include <winuser.h>
#include <wtsapi32.h>
#include <userenv.h>
#include "../utils/logger.hpp"

#pragma comment(lib, "wtsapi32.lib")
#pragma comment(lib, "userenv.lib")

/**
 * execute_lock_screen_remote
 * Helper to escape Session 0 by injecting the lock command into the 
 * active user's interactive desktop.
 */
static bool execute_lock_screen_remote()
{
    DWORD dwSessionId = WTSGetActiveConsoleSessionId();
    if (dwSessionId == 0xFFFFFFFF) {
        utils::log_error("lock_screen_remote: No active console session detected");
        return false;
    }

    HANDLE hUserToken = nullptr;
    if (!WTSQueryUserToken(dwSessionId, &hUserToken)) {
        utils::log_error("lock_screen_remote: WTSQueryUserToken failed for Session " + 
                        std::to_string(dwSessionId) + " (Error: " + std::to_string(GetLastError()) + ")");
        return false;
    }

    bool success = false;
    STARTUPINFOW si = { 0 };
    PROCESS_INFORMATION pi = { 0 };
    si.cb = sizeof(si);
    si.lpDesktop = (LPWSTR)L"winsta0\\default"; 

    // Command: Win+L equivalent via rundll32
    wchar_t szCommand[] = L"rundll32.exe user32.dll,LockWorkStation";

    // Launch in user context
    if (CreateProcessAsUserW(
        hUserToken, nullptr, szCommand, nullptr, nullptr, FALSE, 
        CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi
    )) {
        utils::log_info("lock_screen_remote: Command injected into Session " + std::to_string(dwSessionId));
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        success = true;
    } else {
        utils::log_error("lock_screen_remote: CreateProcessAsUserW failed (Error: " + 
                        std::to_string(GetLastError()) + ")");
    }

    CloseHandle(hUserToken);
    return success;
}

/**
 * execute_lock_screen
 * High-level orchestrator for locking the Windows workstation.
 */
bool execute_lock_screen()
{
    const char* allow = std::getenv("ALLOW_DANGEROUS_OPS");
    if (!allow || std::string(allow) != "1")
    {
        utils::log_info("lock_screen: dry-run (ALLOW_DANGEROUS_OPS not set)");
        return true;
    }

    utils::log_info("lock_screen: initiating workstation lock");

    // Path A: Try Session 0 Workaround (Service context)
    if (execute_lock_screen_remote()) {
        utils::log_info("lock_screen: SUCCESS via remote injection");
        return true;
    }

    // Path B: Direct Lock (Interactive context)
    utils::log_info("lock_screen: remote injection failed/skipped, attempting direct LockWorkStation");
    if (LockWorkStation()) {
        utils::log_info("lock_screen: SUCCESS via direct call");
        return true;
    }

    // Error Diagnosis
    DWORD dwErr = GetLastError();
    utils::log_error("lock_screen: FAILED - All methods exhausted. Final System Error: " + std::to_string(dwErr));

    if (dwErr == ERROR_ACCESS_DENIED) {
        utils::log_error("lock_screen: HINT - Check SeTcbPrivilege (Act as part of OS) or user impersonation rights");
    }

    return false;
}
