#include <vector>
#include <string>
#include <windows.h>
#include <tlhelp32.h>
#include <psapi.h>
#include "../utils/logger.hpp"

// very simple wide->narrow helper (UTF-8-ish via CP_UTF8)
static std::string narrow(const std::wstring &ws)
{
  if (ws.empty())
    return {};
  int len = WideCharToMultiByte(CP_UTF8, 0, ws.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (len <= 0)
    return {};
  std::string s(len - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, ws.c_str(), -1, s.data(), len, nullptr, nullptr);
  return s;
}

std::vector<std::string> execute_process_list(bool include_cmdline)
{
  std::vector<std::string> out;
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap == INVALID_HANDLE_VALUE)
  {
    utils::log_error("process_list: CreateToolhelp32Snapshot failed");
    return out;
  }

  PROCESSENTRY32W pe{};
  pe.dwSize = sizeof(pe);

  if (Process32First(snap, &pe))
  {
    do
    {
      std::wstring wentry = pe.szExeFile;

      if (include_cmdline)
      {
        HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
                                      FALSE, pe.th32ProcessID);
        if (hProcess)
        {
          WCHAR wpath[MAX_PATH]{};
          if (GetModuleFileNameExW(hProcess, nullptr, wpath, MAX_PATH))
          {
            wentry += L" | ";
            wentry += wpath;
          }
          CloseHandle(hProcess);
        }
      }

      out.push_back(narrow(wentry));
    } while (Process32NextW(snap, &pe));
  }
  CloseHandle(snap);
  utils::log_info(std::string("process_list: found ") + std::to_string(out.size()) + " processes");
  return out;
}
