#include "lock_screen_command.hpp"

#include "../kernel/ioctl_client.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <string>

#ifdef _WIN32
#include <windows.h>
#include <wtsapi32.h>
#include <userenv.h>
#pragma comment(lib, "wtsapi32.lib")
#pragma comment(lib, "userenv.lib")
#endif

namespace command
{
namespace
{

constexpr int QERR_LOCK_AUTH_FAILED = 5401;
constexpr int QERR_LOCK_NO_ACTIVE_SESSION = 5402;
constexpr int QERR_LOCK_EXEC_FAILED = 5403;
constexpr int QERR_LOCK_BAD_PARAMS = 5404;
constexpr int QERR_INVALID_OPCODE_CODE = 4002;
constexpr int QERR_NOT_SUPPORTED_CODE = 4004;

struct LockAttemptResult
{
  bool ok{false};
  std::string method;
  std::string reason;
  int win32_error{0};
};

std::string lowercase_copy(std::string value)
{
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c)
                 { return static_cast<char>(std::tolower(c)); });
  return value;
}

std::string now_unix_string()
{
  const auto now = std::chrono::duration_cast<std::chrono::seconds>(
                       std::chrono::system_clock::now().time_since_epoch())
                       .count();
  return std::to_string(now);
}

bool parse_lock_params(const std::string &params_json, std::string &error_reason)
{
  if (params_json.empty())
  {
    return true;
  }

  try
  {
    const auto parsed = nlohmann::json::parse(params_json);
    if (!parsed.is_object())
    {
      error_reason = "lock_screen_bad_params";
      return false;
    }
    return true;
  }
  catch (const std::exception &)
  {
    error_reason = "lock_screen_bad_params";
    return false;
  }
}

bool is_invalid_opcode_response(const KernelExecResult &result)
{
  if (result.status == "invalid_opcode" || result.error_code == QERR_INVALID_OPCODE_CODE)
  {
    return true;
  }
  if (!result.error_message.empty() && result.error_message.find("invalid_opcode") != std::string::npos)
  {
    return true;
  }
  return false;
}

void merge_kernel_meta(const KernelExecResult &result, nlohmann::json &kernel_meta)
{
  if (!result.request_id.empty())
  {
    kernel_meta["request_id"] = result.request_id;
  }
  if (!result.kernel_exec_id.empty())
  {
    kernel_meta["kernel_exec_id"] = result.kernel_exec_id;
  }
  if (!result.timestamp.empty())
  {
    kernel_meta["kernel_timestamp"] = result.timestamp;
  }
}

LockScreenExecutionResult fail_result(int code, const std::string &reason, const std::string &notes, const std::string &meta_json = {})
{
  LockScreenExecutionResult out{};
  out.success = false;
  out.error_code = code;
  out.reason = reason;
  out.notes = notes;
  out.meta_json = meta_json;
  return out;
}

#ifdef _WIN32
LockAttemptResult try_direct_lock()
{
  LockAttemptResult result{};
  if (LockWorkStation())
  {
    result.ok = true;
    result.method = "direct_lockworkstation";
    return result;
  }

  result.reason = "lockworkstation_failed";
  result.win32_error = static_cast<int>(GetLastError());
  return result;
}

LockAttemptResult try_active_session_injection()
{
  LockAttemptResult result{};

  const DWORD session_id = WTSGetActiveConsoleSessionId();
  if (session_id == 0xFFFFFFFF)
  {
    result.reason = "no_active_console_session";
    result.win32_error = ERROR_NO_TOKEN;
    return result;
  }

  HANDLE user_token = nullptr;
  if (!WTSQueryUserToken(session_id, &user_token))
  {
    result.reason = "wts_query_user_token_failed";
    result.win32_error = static_cast<int>(GetLastError());
    return result;
  }

  HANDLE primary_token = nullptr;
  if (!DuplicateTokenEx(
          user_token,
          TOKEN_ASSIGN_PRIMARY | TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ADJUST_DEFAULT | TOKEN_ADJUST_SESSIONID,
          nullptr,
          SecurityImpersonation,
          TokenPrimary,
          &primary_token))
  {
    result.reason = "duplicate_token_failed";
    result.win32_error = static_cast<int>(GetLastError());
    CloseHandle(user_token);
    return result;
  }

  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.lpDesktop = const_cast<LPWSTR>(L"winsta0\\default");
  PROCESS_INFORMATION process_info{};

  wchar_t command_line[] = L"rundll32.exe user32.dll,LockWorkStation";
  const BOOL created = CreateProcessAsUserW(
      primary_token,
      nullptr,
      command_line,
      nullptr,
      nullptr,
      FALSE,
      CREATE_NO_WINDOW,
      nullptr,
      nullptr,
      &startup,
      &process_info);

  if (created)
  {
    (void)WaitForSingleObject(process_info.hProcess, 3000);
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    CloseHandle(primary_token);
    CloseHandle(user_token);

    result.ok = true;
    result.method = "active_session_rundll32";
    return result;
  }

  result.reason = "create_process_as_user_failed";
  result.win32_error = static_cast<int>(GetLastError());
  CloseHandle(primary_token);
  CloseHandle(user_token);
  return result;
}
#endif

} // namespace

bool IsLockScreenMethod(const std::string &method)
{
  const std::string lowered = lowercase_copy(method);
  return lowered == "lock_screen" || lowered == "exec_lock_screen" || lowered == "lock-screen";
}

LockScreenExecutionResult ExecuteLockScreenCommand(
    const AgentState &state,
    const std::string &command_message_id,
    const std::string &params_json)
{
  std::string params_error;
  if (!parse_lock_params(params_json, params_error))
  {
    return fail_result(QERR_LOCK_BAD_PARAMS, params_error, "invalid lock_screen params");
  }

  IoctlClient ioctl;
  auto auth = ioctl.lock_screen(
      command_message_id,
      state,
      command_message_id);

  nlohmann::json kernel_meta = nlohmann::json::object();
  kernel_meta["transport"] = ioctl.using_driver_transport() ? "kernel_ioctl" : "kernel_pipe";
  merge_kernel_meta(auth, kernel_meta);

  if (auth.status != "ok")
  {
    KernelExecResult compat_auth = ioctl.ping(command_message_id, state, command_message_id);
    merge_kernel_meta(compat_auth, kernel_meta);
    if (compat_auth.status == "ok")
    {
      kernel_meta["authorization_mode"] = "compat_ping";
      if (is_invalid_opcode_response(auth))
      {
        kernel_meta["authorization_fallback_reason"] = "invalid_opcode";
      }
      else if (auth.error_code == QERR_NOT_SUPPORTED_CODE)
      {
        kernel_meta["authorization_fallback_reason"] = "not_supported";
      }
      else
      {
        kernel_meta["authorization_fallback_reason"] = "auth_failed";
      }
      kernel_meta["authorization_primary_status"] = auth.status;
      kernel_meta["authorization_primary_error_code"] = auth.error_code;
      if (!auth.error_message.empty())
      {
        kernel_meta["authorization_primary_error_message"] = auth.error_message;
      }
    }
    else
    {
      const int code = auth.error_code != 0
                           ? auth.error_code
                           : (compat_auth.error_code != 0 ? compat_auth.error_code : QERR_LOCK_AUTH_FAILED);
      std::string message = auth.error_message;
      if (message.empty())
      {
        message = compat_auth.error_message;
      }
      if (message.empty())
      {
        message = "kernel authorization failed";
      }
      return fail_result(code, "lock_screen_kernel_authorization_failed", message, kernel_meta.dump());
    }
  }

#ifdef _WIN32
  LockAttemptResult attempt = try_direct_lock();
  if (!attempt.ok)
  {
    const LockAttemptResult injected = try_active_session_injection();
    if (injected.ok)
    {
      attempt = injected;
    }
  }

  if (!attempt.ok)
  {
    kernel_meta["lock_attempt_reason"] = attempt.reason;
    kernel_meta["lock_attempt_win32_error"] = attempt.win32_error;
    const int code = (attempt.reason == "no_active_console_session")
                         ? QERR_LOCK_NO_ACTIVE_SESSION
                         : QERR_LOCK_EXEC_FAILED;
    const std::string notes = attempt.reason + (attempt.win32_error > 0 ? (" (win32=" + std::to_string(attempt.win32_error) + ")") : "");
    return fail_result(code, "lock_screen_execution_failed", notes, kernel_meta.dump());
  }

  nlohmann::json data = {
      {"schema_version", "v1"},
      {"action", "lock_screen"},
      {"kernel_mode", true},
      {"status", "ok"},
      {"lock_method", attempt.method},
      {"collection_ts_unix", now_unix_string()},
  };

  LockScreenExecutionResult success{};
  success.success = true;
  success.notes = "workstation lock initiated";
  success.data_json = data.dump();
  success.meta_json = kernel_meta.dump();
  return success;
#else
  return fail_result(QERR_LOCK_EXEC_FAILED, "unsupported_platform", "lock_screen is only supported on Windows", kernel_meta.dump());
#endif
}

} // namespace command
