#include "collect_system_info.hpp"
#include <windows.h>
#include <sysinfoapi.h>
#include <iostream>
#include <iomanip>
#include <sstream>
#include "../utils/logger.hpp"

// Helper to get OS version without relying on GetVersionEx (which is deprecated)
std::string get_os_version()
{
  HKEY hKey;
  std::string productName = "Windows (Unknown Version)";

  if (RegOpenKeyExA(
          HKEY_LOCAL_MACHINE,
          "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
          0,
          KEY_READ | KEY_WOW64_64KEY,
          &hKey) == ERROR_SUCCESS)
  {
    std::vector<char> buffer(512);
    DWORD size = static_cast<DWORD>(buffer.size());

    if (RegQueryValueExA(
            hKey,
            "ProductName",
            nullptr,
            nullptr,
            reinterpret_cast<LPBYTE>(buffer.data()),
            &size) == ERROR_SUCCESS)
    {
      productName = buffer.data(); // null-terminated string
    }

    RegCloseKey(hKey);
  }

  return productName;
}

std::unordered_map<std::string, std::string> execute_collect_system_info(
    const std::vector<std::string> &fields)
{
  std::unordered_map<std::string, std::string> result;

  // Determine which fields to process
  std::vector<std::string> target_fields = fields;
  if (target_fields.empty())
  {
    target_fields = {"cpu", "ram", "disk", "uptime", "os"};
  }

  for (const auto &field : target_fields)
  {
    if (field == "cpu")
    {
      SYSTEM_INFO si;
      GetSystemInfo(&si);
      result["cpu"] = std::to_string(si.dwNumberOfProcessors) + " cores";
    }
    else if (field == "ram")
    {
      MEMORYSTATUSEX mem;
      mem.dwLength = sizeof(mem);
      if (GlobalMemoryStatusEx(&mem))
      {
        // dwMemoryLoad is % of memory in use
        int pct_free = 100 - static_cast<int>(mem.dwMemoryLoad);
        unsigned long long total_gb = mem.ullTotalPhys / (1024 * 1024 * 1024);
        result["ram"] = std::to_string(pct_free) + "% free (" + std::to_string(total_gb) + "GB total)";
      }
      else
      {
        result["ram"] = "unavailable";
      }
    }
    else if (field == "disk")
    {
      ULARGE_INTEGER total, free;
      // Using nullptr defaults to the current drive; "C:\\" is more explicit for system info
      if (GetDiskFreeSpaceExA("C:\\", &free, &total, nullptr))
      {
        double pct_free = (100.0 * free.QuadPart) / total.QuadPart;
        result["disk"] = std::to_string(static_cast<int>(pct_free)) + "% free";
      }
      else
      {
        result["disk"] = "unavailable";
      }
    }
    else if (field == "uptime")
    {
      // GetTickCount64 returns milliseconds since boot
      ULONGLONG seconds = GetTickCount64() / 1000;
      ULONGLONG hours = seconds / 3600;
      ULONGLONG mins = (seconds % 3600) / 60;
      result["uptime"] = std::to_string(hours) + "h " + std::to_string(mins) + "m";
    }
    else if (field == "os")
    {
      result["os"] = get_os_version();
    }
    else
    {
      result[field] = "unsupported";
    }
  }

  utils::log_info("collect_system_info: processed " + std::to_string(result.size()) + " fields");
  return result;
}
