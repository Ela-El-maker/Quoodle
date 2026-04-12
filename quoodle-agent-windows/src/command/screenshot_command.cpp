#include "screenshot_command.hpp"

#include "artifact_client.hpp"

#include "../kernel/ioctl_client.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

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

constexpr int QERR_SCREENSHOT_AUTH_FAILED = 5201;
constexpr int QERR_SCREENSHOT_NO_ACTIVE_SESSION = 5202;
constexpr int QERR_SCREENSHOT_HELPER_LAUNCH_FAILED = 5203;
constexpr int QERR_SCREENSHOT_HELPER_TIMEOUT = 5204;
constexpr int QERR_SCREENSHOT_CAPTURE_FAILED = 5205;
constexpr int QERR_SCREENSHOT_UPLOAD_REQUEST_FAILED = 5206;
constexpr int QERR_SCREENSHOT_UPLOAD_FAILED = 5207;
constexpr int QERR_SCREENSHOT_BAD_PARAMS = 5208;

struct ScreenshotParams
{
  std::string resolution{"original"};
  std::string format{"png"};
  int jpeg_quality{85};
};

struct HelperLaunchResult
{
  bool ok{false};
  std::string reason;
  std::string detail;
};

std::string lowercase_copy(std::string value)
{
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c)
                 { return static_cast<char>(std::tolower(c)); });
  return value;
}

bool parse_screenshot_params(const std::string &params_json, ScreenshotParams &out, std::string &error_reason)
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
      error_reason = "screenshot_bad_params";
      return false;
    }

    if (parsed.contains("resolution") && parsed["resolution"].is_string())
    {
      out.resolution = lowercase_copy(parsed["resolution"].get<std::string>());
    }
    if (parsed.contains("format") && parsed["format"].is_string())
    {
      out.format = lowercase_copy(parsed["format"].get<std::string>());
    }
    if (parsed.contains("quality") && parsed["quality"].is_number_integer())
    {
      out.jpeg_quality = parsed["quality"].get<int>();
    }
  }
  catch (const std::exception &)
  {
    error_reason = "screenshot_bad_params";
    return false;
  }

  if (out.resolution != "original" && out.resolution != "1080p" && out.resolution != "720p")
  {
    error_reason = "screenshot_bad_params";
    return false;
  }
  if (out.format != "png" && out.format != "jpeg")
  {
    error_reason = "screenshot_bad_params";
    return false;
  }
  out.jpeg_quality = std::max(1, std::min(100, out.jpeg_quality));
  return true;
}

std::string current_timestamp_slug()
{
  const auto now = std::chrono::duration_cast<std::chrono::seconds>(
                       std::chrono::system_clock::now().time_since_epoch())
                       .count();
  return std::to_string(now);
}

std::filesystem::path screenshot_temp_root()
{
  const char *program_data = std::getenv("ProgramData");
  const std::filesystem::path root = (program_data && *program_data)
                                         ? std::filesystem::path(program_data)
                                         : std::filesystem::path("C:/ProgramData");
  return root / "Quoodle" / "artifacts";
}

bool read_text_file(const std::filesystem::path &path, std::string &out)
{
  std::ifstream file(path, std::ios::binary);
  if (!file)
  {
    return false;
  }
  std::ostringstream buffer;
  buffer << file.rdbuf();
  out = buffer.str();
  return true;
}

#ifdef _WIN32
std::string current_executable_path()
{
  char path[MAX_PATH] = {};
  const DWORD len = GetModuleFileNameA(nullptr, path, MAX_PATH);
  if (len == 0 || len >= MAX_PATH)
  {
    return {};
  }
  return std::string(path, len);
}

std::string build_helper_command_line(
    const std::string &exe_path,
    const std::string &output_path,
    const std::string &meta_path,
    const ScreenshotParams &params)
{
  if (exe_path.empty())
  {
    return {};
  }

  std::ostringstream command;
  command << "\"" << exe_path << "\""
          << " --screenshot-helper"
          << " --output \"" << output_path << "\""
          << " --meta \"" << meta_path << "\""
          << " --format " << params.format
          << " --resolution " << params.resolution
          << " --quality " << params.jpeg_quality;
  return command.str();
}

HelperLaunchResult wait_for_helper_process(
    PROCESS_INFORMATION &process_info,
    std::uint32_t timeout_ms)
{
  HelperLaunchResult result{};

  const DWORD wait_status = WaitForSingleObject(process_info.hProcess, timeout_ms);
  if (wait_status == WAIT_TIMEOUT)
  {
    TerminateProcess(process_info.hProcess, 1);
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    result.reason = "screenshot_helper_timeout";
    return result;
  }

  DWORD exit_code = 1;
  GetExitCodeProcess(process_info.hProcess, &exit_code);
  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);

  if (exit_code != 0)
  {
    result.reason = "screenshot_helper_failed";
    result.detail = "helper_exit_" + std::to_string(exit_code);
    return result;
  }

  result.ok = true;
  return result;
}

HelperLaunchResult run_helper_in_current_session(
    const std::string &output_path,
    const std::string &meta_path,
    const ScreenshotParams &params,
    std::uint32_t timeout_ms)
{
  HelperLaunchResult result{};
  const std::string exe_path = current_executable_path();
  if (exe_path.empty())
  {
    result.reason = "screenshot_helper_launch_failed";
    result.detail = "missing_executable_path";
    return result;
  }

  const std::string command_line = build_helper_command_line(exe_path, output_path, meta_path, params);
  if (command_line.empty())
  {
    result.reason = "screenshot_helper_launch_failed";
    result.detail = "build_command_line_failed";
    return result;
  }

  std::vector<char> command_buffer(command_line.begin(), command_line.end());
  command_buffer.push_back('\0');

  STARTUPINFOA startup{};
  startup.cb = sizeof(startup);
  startup.lpDesktop = const_cast<LPSTR>("winsta0\\default");
  PROCESS_INFORMATION process_info{};

  const BOOL created = CreateProcessA(
      nullptr,
      command_buffer.data(),
      nullptr,
      nullptr,
      FALSE,
      CREATE_NO_WINDOW,
      nullptr,
      nullptr,
      &startup,
      &process_info);

  if (!created)
  {
    result.reason = "screenshot_helper_launch_failed";
    result.detail = "create_process_failed_" + std::to_string(GetLastError());
    return result;
  }

  return wait_for_helper_process(process_info, timeout_ms);
}

HelperLaunchResult run_helper_in_active_session(
    const std::string &output_path,
    const std::string &meta_path,
    const ScreenshotParams &params,
    std::uint32_t timeout_ms)
{
  HelperLaunchResult result{};
  const DWORD session_id = WTSGetActiveConsoleSessionId();
  if (session_id == 0xFFFFFFFF)
  {
    result.reason = "screenshot_no_active_session";
    return result;
  }

  HANDLE user_token = nullptr;
  if (!WTSQueryUserToken(session_id, &user_token))
  {
    const DWORD wts_error = GetLastError();
    // Local/dev runs often execute the agent as an interactive user process,
    // where WTSQueryUserToken requires privileges that are unavailable.
    // In that case, launch the helper in the current session.
    if (wts_error == ERROR_ACCESS_DENIED || wts_error == ERROR_PRIVILEGE_NOT_HELD)
    {
      HelperLaunchResult fallback = run_helper_in_current_session(output_path, meta_path, params, timeout_ms);
      if (fallback.ok)
      {
        return fallback;
      }

      result.reason = fallback.reason.empty() ? "screenshot_helper_launch_failed" : fallback.reason;
      result.detail = "wts_query_user_token_failed_" + std::to_string(wts_error);
      if (!fallback.detail.empty())
      {
        result.detail += "; " + fallback.detail;
      }
      return result;
    }

    result.reason = "screenshot_no_active_session";
    result.detail = "wts_query_user_token_failed_" + std::to_string(wts_error);
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
    CloseHandle(user_token);
    result.reason = "screenshot_helper_launch_failed";
    result.detail = "duplicate_token_failed";
    return result;
  }

  LPVOID env_block = nullptr;
  if (!CreateEnvironmentBlock(&env_block, primary_token, FALSE))
  {
    env_block = nullptr;
  }

  const std::string exe_path = current_executable_path();
  if (exe_path.empty())
  {
    if (env_block)
      DestroyEnvironmentBlock(env_block);
    CloseHandle(primary_token);
    CloseHandle(user_token);
    result.reason = "screenshot_helper_launch_failed";
    result.detail = "missing_executable_path";
    return result;
  }

  std::string command_line = build_helper_command_line(exe_path, output_path, meta_path, params);
  if (command_line.empty())
  {
    if (env_block)
      DestroyEnvironmentBlock(env_block);
    CloseHandle(primary_token);
    CloseHandle(user_token);
    result.reason = "screenshot_helper_launch_failed";
    result.detail = "build_command_line_failed";
    return result;
  }

  std::vector<char> command_buffer(command_line.begin(), command_line.end());
  command_buffer.push_back('\0');

  STARTUPINFOA startup{};
  startup.cb = sizeof(startup);
  startup.lpDesktop = const_cast<LPSTR>("winsta0\\default");
  PROCESS_INFORMATION process_info{};

  const DWORD flags = CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW;
  const BOOL created = CreateProcessAsUserA(
      primary_token,
      nullptr,
      command_buffer.data(),
      nullptr,
      nullptr,
      FALSE,
      flags,
      env_block,
      nullptr,
      &startup,
      &process_info);

  if (env_block)
  {
    DestroyEnvironmentBlock(env_block);
  }
  CloseHandle(primary_token);
  CloseHandle(user_token);

  if (!created)
  {
    result.reason = "screenshot_helper_launch_failed";
    result.detail = "create_process_as_user_failed_" + std::to_string(GetLastError());
    return result;
  }

  return wait_for_helper_process(process_info, timeout_ms);
}
#endif

ScreenshotExecutionResult fail_result(int code, const std::string &reason, const std::string &notes, const std::string &meta_json = {})
{
  ScreenshotExecutionResult out{};
  out.success = false;
  out.error_code = code;
  out.reason = reason;
  out.notes = notes;
  out.meta_json = meta_json;
  return out;
}

} // namespace

bool IsScreenshotMethod(const std::string &method)
{
  const std::string lowered = lowercase_copy(method);
  return lowered == "screenshot" || lowered == "screenshot-capture";
}

ScreenshotExecutionResult ExecuteScreenshotCommand(
    const AgentConfig &config,
    const AgentState &state,
    const std::string &command_message_id,
    const std::string &params_json)
{
  ScreenshotParams params{};
  std::string params_error;
  if (!parse_screenshot_params(params_json, params, params_error))
  {
    return fail_result(QERR_SCREENSHOT_BAD_PARAMS, params_error, "invalid screenshot params");
  }

  IoctlClient ioctl;
  const auto auth = ioctl.capture_screenshot_authorize(
      command_message_id,
      state,
      command_message_id,
      params_json.empty() ? "{}" : params_json);

  nlohmann::json kernel_meta = nlohmann::json::object();
  kernel_meta["transport"] = ioctl.using_driver_transport() ? "kernel_ioctl" : "kernel_pipe";
  if (!auth.request_id.empty())
    kernel_meta["request_id"] = auth.request_id;
  if (!auth.kernel_exec_id.empty())
    kernel_meta["kernel_exec_id"] = auth.kernel_exec_id;
  if (!auth.timestamp.empty())
    kernel_meta["kernel_timestamp"] = auth.timestamp;
  const std::string kernel_meta_json = kernel_meta.dump();

  if (auth.status != "ok")
  {
    return fail_result(
        auth.error_code != 0 ? auth.error_code : QERR_SCREENSHOT_AUTH_FAILED,
        "screenshot_kernel_authorization_failed",
        auth.error_message.empty() ? "kernel authorization failed" : auth.error_message,
        kernel_meta_json);
  }

  nlohmann::json authorize_payload = nlohmann::json::object();
  if (!auth.result.empty())
  {
    try
    {
      authorize_payload = nlohmann::json::parse(auth.result);
    }
    catch (const std::exception &)
    {
      authorize_payload["status"] = auth.result;
    }
  }

  const std::filesystem::path temp_root = screenshot_temp_root();
  std::error_code ec;
  std::filesystem::create_directories(temp_root, ec);
  const std::string stamp = current_timestamp_slug();
  const std::string extension = params.format == "jpeg" ? ".jpg" : ".png";
  const std::filesystem::path output_path = temp_root / ("shot_" + command_message_id + "_" + stamp + extension);
  const std::filesystem::path meta_path = temp_root / ("shot_" + command_message_id + "_" + stamp + ".meta.json");
  auto cleanup_temp = [&]()
  {
    std::filesystem::remove(output_path, ec);
    std::filesystem::remove(meta_path, ec);
  };

#ifdef _WIN32
  const auto helper = run_helper_in_active_session(output_path.string(), meta_path.string(), params, 30000);
  if (!helper.ok)
  {
    cleanup_temp();
    const int code = helper.reason == "screenshot_no_active_session" ? QERR_SCREENSHOT_NO_ACTIVE_SESSION
                   : helper.reason == "screenshot_helper_timeout"     ? QERR_SCREENSHOT_HELPER_TIMEOUT
                                                                       : QERR_SCREENSHOT_HELPER_LAUNCH_FAILED;
    const std::string notes = helper.detail.empty() ? helper.reason : helper.reason + ": " + helper.detail;
    return fail_result(code, helper.reason, notes, kernel_meta_json);
  }
#else
  return fail_result(QERR_SCREENSHOT_CAPTURE_FAILED, "screenshot_unsupported_platform", "screenshot capture is unsupported on this platform", kernel_meta_json);
#endif

  std::string meta_contents;
  if (!read_text_file(meta_path, meta_contents))
  {
    cleanup_temp();
    return fail_result(
        QERR_SCREENSHOT_CAPTURE_FAILED,
        "screenshot_helper_failed",
        "missing helper metadata",
        kernel_meta_json);
  }

  nlohmann::json capture_meta = nlohmann::json::object();
  try
  {
    capture_meta = nlohmann::json::parse(meta_contents);
  }
  catch (const std::exception &)
  {
    cleanup_temp();
    return fail_result(
        QERR_SCREENSHOT_CAPTURE_FAILED,
        "screenshot_helper_failed",
        "invalid helper metadata payload",
        kernel_meta_json);
  }

  if (capture_meta.value("status", "") != "ok")
  {
    cleanup_temp();
    const std::string reason = capture_meta.value("reason", "screenshot_helper_failed");
    return fail_result(
        QERR_SCREENSHOT_CAPTURE_FAILED,
        reason,
        "helper capture failed",
        kernel_meta_json);
  }

  const std::uint64_t size_bytes = capture_meta.value("size_bytes", static_cast<std::uint64_t>(0));
  const std::string content_type = params.format == "jpeg" ? "image/jpeg" : "image/png";
  ArtifactClient artifacts;
  const std::string artifact_base_url = config.artifact_api_base_url.empty()
                                            ? config.telemetry_fallback_url
                                            : config.artifact_api_base_url;
  const auto ticket = artifacts.request_upload(
      artifact_base_url,
      config.jwt,
      command_message_id,
      content_type,
      size_bytes,
      config.connection_timeout_ms);
  if (!ticket.ok)
  {
    cleanup_temp();
    return fail_result(
        QERR_SCREENSHOT_UPLOAD_REQUEST_FAILED,
        "screenshot_upload_request_failed",
        ticket.reason,
        kernel_meta_json);
  }

  const auto upload = artifacts.upload_file(
      ticket.upload_url,
      config.jwt,
      ticket.artifact_id,
      ticket.upload_token,
      output_path.string(),
      std::max<std::uint32_t>(config.connection_timeout_ms, 20000U));
  if (!upload.ok)
  {
    cleanup_temp();
    return fail_result(
        QERR_SCREENSHOT_UPLOAD_FAILED,
        "screenshot_upload_failed",
        upload.reason,
        kernel_meta_json);
  }

  // Never leak client-local artifact filesystem paths into server-stored results.
  capture_meta.erase("output_path");

  nlohmann::json data = {
      {"schema_version", "v1"},
      {"snapshot_type", "screenshot"},
      {"kernel_mode", true},
      {"format", params.format},
      {"resolution", params.resolution},
      {"capture", capture_meta},
      {"authorization", authorize_payload},
  };

  cleanup_temp();

  ScreenshotExecutionResult success{};
  success.success = true;
  success.notes = "screenshot captured and uploaded";
  success.artifact_url = upload.artifact_url;
  success.artifact_checksum = upload.artifact_checksum;
  success.data_json = data.dump();
  success.meta_json = kernel_meta_json;
  return success;
}

} // namespace command
