#include <string>
#include <windows.h>
#include "../utils/logger.hpp"

bool execute_shutdown(bool force)
{
  const char *allow = std::getenv("ALLOW_DANGEROUS_OPS");
  if (!allow || std::string(allow) != "1")
  {
    utils::log_info("shutdown: dry-run (ALLOW_DANGEROUS_OPS not set)");
    return true;
  }

  DWORD flags = EWX_POWEROFF;
  if (force)
    flags |= EWX_FORCE;

  utils::log_info(std::string("shutdown: requesting power-off, force=") +
                  (force ? "true" : "false"));

  BOOL ok = ExitWindowsEx(flags, SHTDN_REASON_MAJOR_SOFTWARE);
  if (!ok)
  {
    DWORD err = GetLastError();
    utils::log_error("shutdown: ExitWindowsEx failed, error=" +
                     std::to_string(err));
  }

  return ok != 0;
}
