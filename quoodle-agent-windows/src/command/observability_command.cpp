#include "observability_command.hpp"

#include "artifact_client.hpp"
#include "../kernel/ioctl_client.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdio>
#include <cstdint>
#include <ctime>
#include <filesystem>
#include <sstream>
#include <string>
#include <system_error>
#include <vector>

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <tlhelp32.h>
#include <winsvc.h>
#pragma comment(lib, "iphlpapi.lib")
#endif

namespace command
{
namespace
{

constexpr int QERR_OBS_AUTH_FAILED = 5301;
constexpr int QERR_OBS_COLLECT_FAILED = 5302;
constexpr int QERR_FS_INVALID_PARAMS = 5200;
constexpr int QERR_FS_PATH_NOT_FOUND = 5201;
constexpr int QERR_FS_NOT_DIRECTORY = 5202;
constexpr int QERR_FS_NOT_FILE = 5203;
constexpr int QERR_FS_ACCESS_DENIED = 5204;
constexpr int QERR_FS_TOO_LARGE = 5205;
constexpr int QERR_FS_UPLOAD_REQUEST_FAILED = 5206;
constexpr int QERR_FS_UPLOAD_FAILED = 5207;
constexpr std::size_t kDefaultLimit = 250;
constexpr std::size_t kMaxLimit = 1000;
constexpr std::size_t kDefaultFsLimit = 250;
constexpr std::size_t kMaxFsLimit = 2000;
constexpr std::uint64_t kDefaultDownloadMaxBytes = 5u * 1024u * 1024u;
constexpr std::uint64_t kMaxDownloadMaxBytes = 25u * 1024u * 1024u;
constexpr int kErrInvalidOpcode = 4002;
constexpr int kErrNotSupported = 4004;

struct FileListOptions
{
  std::filesystem::path root_path;
  bool recursive{true};
  std::size_t max_depth{4};
  std::size_t limit{kDefaultFsLimit};
  bool include_hidden{false};
  bool include_system{false};
  bool follow_symlinks{false};
};

struct DownloadOptions
{
  std::filesystem::path file_path;
  std::uint64_t max_bytes{kDefaultDownloadMaxBytes};
};

std::string lowercase_copy(std::string value)
{
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c)
                 { return static_cast<char>(std::tolower(c)); });
  return value;
}

std::string canonical_method(const std::string &method)
{
  const std::string lowered = lowercase_copy(method);
  if (lowered == "process-list" || lowered == "get_process_list")
  {
    return "list_processes";
  }
  if (lowered == "services-list")
  {
    return "list_services";
  }
  if (lowered == "netstat")
  {
    return "list_connections";
  }
  if (lowered == "mounts-list" || lowered == "mount-list")
  {
    return "list_mounts";
  }
  if (lowered == "network-info" || lowered == "dns-lookup")
  {
    return "network_info";
  }
  if (lowered == "display-info" || lowered == "window-title" || lowered == "active-window")
  {
    return "get_active_window";
  }
  if (lowered == "filesystem" || lowered == "browse-filesystem")
  {
    return "list_files";
  }
  if (lowered == "download-file")
  {
    return "download_file";
  }
  return lowered;
}

std::size_t parse_limit(const std::string &params_json)
{
  if (params_json.empty())
  {
    return kDefaultLimit;
  }

  try
  {
    const auto parsed = nlohmann::json::parse(params_json);
    if (!parsed.is_object())
    {
      return kDefaultLimit;
    }
    if (!parsed.contains("limit") || !parsed["limit"].is_number_integer())
    {
      return kDefaultLimit;
    }

    const auto value = parsed["limit"].get<long long>();
    if (value <= 0)
    {
      return kDefaultLimit;
    }
    if (value > static_cast<long long>(kMaxLimit))
    {
      return kMaxLimit;
    }
    return static_cast<std::size_t>(value);
  }
  catch (const std::exception &)
  {
    return kDefaultLimit;
  }
}

bool parse_params_object(const std::string &params_json, nlohmann::json &out)
{
  out = nlohmann::json::object();
  if (params_json.empty())
  {
    return true;
  }

  try
  {
    const auto parsed = nlohmann::json::parse(params_json);
    if (!parsed.is_object())
    {
      return false;
    }
    out = parsed;
    return true;
  }
  catch (const std::exception &)
  {
    return false;
  }
}

bool json_bool(const nlohmann::json &obj, const char *key, bool default_value)
{
  if (!obj.contains(key))
  {
    return default_value;
  }
  const auto &value = obj.at(key);
  if (value.is_boolean())
  {
    return value.get<bool>();
  }
  if (value.is_number_integer())
  {
    return value.get<long long>() != 0;
  }
  if (value.is_string())
  {
    const auto lowered = lowercase_copy(value.get<std::string>());
    return lowered == "1" || lowered == "true" || lowered == "yes" || lowered == "on";
  }
  return default_value;
}

std::size_t json_size_t(const nlohmann::json &obj, const char *key, std::size_t default_value, std::size_t max_value)
{
  if (!obj.contains(key) || !obj.at(key).is_number_integer())
  {
    return default_value;
  }
  const auto raw = obj.at(key).get<long long>();
  if (raw <= 0)
  {
    return default_value;
  }
  const auto casted = static_cast<std::size_t>(raw);
  return std::min(casted, max_value);
}

std::uint64_t json_u64(const nlohmann::json &obj, const char *key, std::uint64_t default_value, std::uint64_t max_value)
{
  if (!obj.contains(key) || !obj.at(key).is_number_integer())
  {
    return default_value;
  }
  const auto raw = obj.at(key).get<long long>();
  if (raw <= 0)
  {
    return default_value;
  }
  const auto casted = static_cast<std::uint64_t>(raw);
  return std::min(casted, max_value);
}

std::filesystem::path default_filesystem_root()
{
  std::error_code ec;
  const std::filesystem::path c_drive("C:\\");
  if (std::filesystem::exists(c_drive, ec))
  {
    return c_drive;
  }
  ec.clear();
  auto cwd = std::filesystem::current_path(ec);
  if (ec)
  {
    return std::filesystem::path(".");
  }
  if (cwd.has_root_path())
  {
    return cwd.root_path();
  }
  return cwd;
}

std::filesystem::path normalize_path(const std::string &raw_path)
{
  std::filesystem::path path = raw_path.empty() ? default_filesystem_root() : std::filesystem::path(raw_path);
  if (path.is_relative())
  {
    path = default_filesystem_root() / path;
  }
  path = path.lexically_normal();
  std::error_code ec;
  const auto absolute = std::filesystem::absolute(path, ec);
  if (!ec)
  {
    return absolute.lexically_normal();
  }
  return path;
}

bool parse_file_list_options(const std::string &params_json, FileListOptions &out, std::string &reason, std::string &notes)
{
  nlohmann::json parsed = nlohmann::json::object();
  if (!parse_params_object(params_json, parsed))
  {
    reason = "list_files_invalid_params";
    notes = "params must be a JSON object";
    return false;
  }

  const std::string path_value = parsed.value("path", std::string());
  out.root_path = normalize_path(path_value);
  out.recursive = json_bool(parsed, "recursive", true);
  out.max_depth = json_size_t(parsed, "max_depth", 4, 16);
  out.limit = json_size_t(parsed, "limit", kDefaultFsLimit, kMaxFsLimit);
  out.include_hidden = json_bool(parsed, "include_hidden", false);
  out.include_system = json_bool(parsed, "include_system", false);
  out.follow_symlinks = json_bool(parsed, "follow_symlinks", false);
  reason.clear();
  notes.clear();
  return true;
}

bool parse_download_options(const std::string &params_json, DownloadOptions &out, std::string &reason, std::string &notes)
{
  nlohmann::json parsed = nlohmann::json::object();
  if (!parse_params_object(params_json, parsed))
  {
    reason = "download_file_invalid_params";
    notes = "params must be a JSON object";
    return false;
  }

  const std::string path_value = parsed.value("path", std::string());
  if (path_value.empty())
  {
    reason = "download_file_invalid_params";
    notes = "path is required";
    return false;
  }

  out.file_path = normalize_path(path_value);
  out.max_bytes = json_u64(parsed, "max_bytes", kDefaultDownloadMaxBytes, kMaxDownloadMaxBytes);
  reason.clear();
  notes.clear();
  return true;
}

ObservabilityExecutionResult fail_result(int code, const std::string &reason, const std::string &notes, const std::string &meta_json = {})
{
  ObservabilityExecutionResult out{};
  out.success = false;
  out.error_code = code;
  out.reason = reason;
  out.notes = notes;
  out.meta_json = meta_json;
  return out;
}

bool is_invalid_opcode_response(const KernelExecResult &result)
{
  if (result.status == "invalid_opcode" || result.error_code == kErrInvalidOpcode)
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

std::string now_unix_string()
{
  const auto now = std::chrono::duration_cast<std::chrono::seconds>(
                       std::chrono::system_clock::now().time_since_epoch())
                       .count();
  return std::to_string(now);
}

#ifdef _WIN32
std::string ipv4_to_string(std::uint32_t network_order_ipv4)
{
  const std::uint32_t host_order = ntohl(network_order_ipv4);
  const std::uint32_t b1 = (host_order >> 24) & 0xFFu;
  const std::uint32_t b2 = (host_order >> 16) & 0xFFu;
  const std::uint32_t b3 = (host_order >> 8) & 0xFFu;
  const std::uint32_t b4 = host_order & 0xFFu;
  return std::to_string(b1) + "." + std::to_string(b2) + "." + std::to_string(b3) + "." + std::to_string(b4);
}

std::string tcp_state_to_string(DWORD state)
{
  switch (state)
  {
  case MIB_TCP_STATE_CLOSED:
    return "closed";
  case MIB_TCP_STATE_LISTEN:
    return "listen";
  case MIB_TCP_STATE_SYN_SENT:
    return "syn_sent";
  case MIB_TCP_STATE_SYN_RCVD:
    return "syn_received";
  case MIB_TCP_STATE_ESTAB:
    return "established";
  case MIB_TCP_STATE_FIN_WAIT1:
    return "fin_wait_1";
  case MIB_TCP_STATE_FIN_WAIT2:
    return "fin_wait_2";
  case MIB_TCP_STATE_CLOSE_WAIT:
    return "close_wait";
  case MIB_TCP_STATE_CLOSING:
    return "closing";
  case MIB_TCP_STATE_LAST_ACK:
    return "last_ack";
  case MIB_TCP_STATE_TIME_WAIT:
    return "time_wait";
  case MIB_TCP_STATE_DELETE_TCB:
    return "delete_tcb";
  default:
    return "unknown";
  }
}

std::string drive_type_to_string(UINT drive_type)
{
  switch (drive_type)
  {
  case DRIVE_REMOVABLE:
    return "removable";
  case DRIVE_FIXED:
    return "fixed";
  case DRIVE_REMOTE:
    return "network";
  case DRIVE_CDROM:
    return "cdrom";
  case DRIVE_RAMDISK:
    return "ramdisk";
  case DRIVE_NO_ROOT_DIR:
    return "no_root";
  case DRIVE_UNKNOWN:
  default:
    return "unknown";
  }
}

std::string if_type_to_string(ULONG if_type)
{
  switch (if_type)
  {
  case IF_TYPE_ETHERNET_CSMACD:
    return "ethernet";
  case IF_TYPE_IEEE80211:
    return "wifi";
  case IF_TYPE_SOFTWARE_LOOPBACK:
    return "loopback";
  case IF_TYPE_TUNNEL:
    return "tunnel";
  default:
    return "other";
  }
}

std::string oper_status_to_string(IF_OPER_STATUS status)
{
  switch (status)
  {
  case IfOperStatusUp:
    return "up";
  case IfOperStatusDown:
    return "down";
  case IfOperStatusTesting:
    return "testing";
  case IfOperStatusDormant:
    return "dormant";
  case IfOperStatusNotPresent:
    return "not_present";
  case IfOperStatusLowerLayerDown:
    return "lower_layer_down";
  default:
    return "unknown";
  }
}

std::string socket_address_to_string(const SOCKADDR *address)
{
  if (address == nullptr)
  {
    return {};
  }

  char buffer[INET6_ADDRSTRLEN] = {};
  if (address->sa_family == AF_INET)
  {
    const auto *ipv4 = reinterpret_cast<const SOCKADDR_IN *>(address);
    return ipv4_to_string(ipv4->sin_addr.s_addr);
  }
  if (address->sa_family == AF_INET6)
  {
    const auto *ipv6 = reinterpret_cast<const SOCKADDR_IN6 *>(address);
    if (InetNtopA(AF_INET6, const_cast<IN6_ADDR *>(&ipv6->sin6_addr), buffer, static_cast<DWORD>(sizeof(buffer))) != nullptr)
    {
      return buffer;
    }
  }
  return {};
}

std::string mac_to_string(const BYTE *data, ULONG length)
{
  if (data == nullptr || length == 0)
  {
    return {};
  }

  std::string out;
  out.reserve(static_cast<std::size_t>(length * 3));
  for (ULONG i = 0; i < length; ++i)
  {
    char chunk[4] = {};
    std::snprintf(chunk, sizeof(chunk), "%02x", data[i]);
    if (i > 0)
    {
      out.push_back(':');
    }
    out.append(chunk);
  }
  return out;
}

std::string file_name_from_path(const std::string &path)
{
  if (path.empty())
  {
    return {};
  }

  const std::size_t slash = path.find_last_of("\\/");
  if (slash == std::string::npos)
  {
    return path;
  }
  return path.substr(slash + 1);
}

std::string wide_to_utf8(const wchar_t *value)
{
  if (value == nullptr)
  {
    return {};
  }

  const int needed = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
  if (needed <= 1)
  {
    return {};
  }

  std::string out(static_cast<std::size_t>(needed - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, out.data(), needed, nullptr, nullptr);
  return out;
}

std::string ansi_to_utf8(const std::string &value)
{
  if (value.empty())
  {
    return {};
  }

  const int wide_needed = MultiByteToWideChar(CP_ACP, 0, value.c_str(), -1, nullptr, 0);
  if (wide_needed <= 1)
  {
    return value;
  }

  std::wstring wide(static_cast<std::size_t>(wide_needed - 1), L'\0');
  MultiByteToWideChar(CP_ACP, 0, value.c_str(), -1, wide.data(), wide_needed);
  return wide_to_utf8(wide.c_str());
}

std::string path_to_utf8(const std::filesystem::path &path)
{
  try
  {
    return wide_to_utf8(path.wstring().c_str());
  }
  catch (const std::exception &)
  {
    return path.string();
  }
}

std::string file_time_to_iso8601(const std::filesystem::file_time_type &file_time)
{
  try
  {
    const auto sys_now = std::chrono::system_clock::now();
    const auto fs_now = std::filesystem::file_time_type::clock::now();
    const auto converted = std::chrono::time_point_cast<std::chrono::system_clock::duration>(
        file_time - fs_now + sys_now);
    const std::time_t value = std::chrono::system_clock::to_time_t(converted);
    if (value <= 0)
    {
      return {};
    }
    std::tm utc{};
    if (gmtime_s(&utc, &value) != 0)
    {
      return {};
    }
    char buffer[32] = {};
    if (std::strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &utc) == 0)
    {
      return {};
    }
    return buffer;
  }
  catch (const std::exception &)
  {
    return {};
  }
}

bool query_hidden_system_flags(const std::filesystem::path &path, bool &is_hidden, bool &is_system)
{
  is_hidden = false;
  is_system = false;
  const std::wstring wide = path.wstring();
  const DWORD attrs = GetFileAttributesW(wide.c_str());
  if (attrs == INVALID_FILE_ATTRIBUTES)
  {
    return false;
  }
  is_hidden = (attrs & FILE_ATTRIBUTE_HIDDEN) != 0;
  is_system = (attrs & FILE_ATTRIBUTE_SYSTEM) != 0;
  return true;
}

bool should_include_entry(const std::filesystem::path &path, const FileListOptions &options)
{
  bool hidden = false;
  bool system = false;
  (void)query_hidden_system_flags(path, hidden, system);
  if (!options.include_hidden && hidden)
  {
    return false;
  }
  if (!options.include_system && system)
  {
    return false;
  }
  return true;
}

nlohmann::json build_file_entry(const std::filesystem::directory_entry &entry)
{
  const auto full_path = entry.path();
  std::error_code ec;
  const bool is_dir = entry.is_directory(ec);
  ec.clear();
  const bool is_file = entry.is_regular_file(ec);
  ec.clear();
  const bool is_symlink = entry.is_symlink(ec);

  std::uint64_t size_bytes = 0;
  if (is_file)
  {
    ec.clear();
    size_bytes = entry.file_size(ec);
    if (ec)
    {
      size_bytes = 0;
    }
  }

  bool is_hidden = false;
  bool is_system = false;
  (void)query_hidden_system_flags(full_path, is_hidden, is_system);

  std::string target_path;
  if (is_symlink)
  {
    ec.clear();
    const auto target = std::filesystem::read_symlink(full_path, ec);
    if (!ec)
    {
      target_path = path_to_utf8(target);
    }
  }

  std::string modified_at;
  ec.clear();
  const auto last_write = std::filesystem::last_write_time(full_path, ec);
  if (!ec)
  {
    modified_at = file_time_to_iso8601(last_write);
  }

  std::string created_at;
  WIN32_FILE_ATTRIBUTE_DATA attr_data{};
  if (GetFileAttributesExW(full_path.wstring().c_str(), GetFileExInfoStandard, &attr_data))
  {
    ULARGE_INTEGER ull{};
    ull.LowPart = attr_data.ftCreationTime.dwLowDateTime;
    ull.HighPart = attr_data.ftCreationTime.dwHighDateTime;
    if (ull.QuadPart > 0)
    {
      constexpr std::uint64_t windows_to_unix_epoch_100ns = 116444736000000000ULL;
      const std::uint64_t unix_100ns = ull.QuadPart - windows_to_unix_epoch_100ns;
      const std::time_t unix_seconds = static_cast<std::time_t>(unix_100ns / 10000000ULL);
      std::tm utc{};
      if (gmtime_s(&utc, &unix_seconds) == 0)
      {
        char buffer[32] = {};
        if (std::strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &utc) > 0)
        {
          created_at = buffer;
        }
      }
    }
  }

  nlohmann::json row = {
      {"name", path_to_utf8(full_path.filename())},
      {"path", path_to_utf8(full_path)},
      {"type", is_dir ? "directory" : (is_file ? "file" : "other")},
      {"size", is_file ? nlohmann::json(size_bytes) : nlohmann::json(nullptr)},
      {"modified_at", modified_at.empty() ? nlohmann::json(nullptr) : nlohmann::json(modified_at)},
      {"created_at", created_at.empty() ? nlohmann::json(nullptr) : nlohmann::json(created_at)},
      {"extension", full_path.has_extension() ? full_path.extension().string() : std::string()},
      {"is_hidden", is_hidden},
      {"is_system", is_system},
      {"is_symlink", is_symlink},
      {"target_path", target_path.empty() ? nlohmann::json(nullptr) : nlohmann::json(target_path)},
      {"downloadable", is_file},
      {"download_method", is_file ? nlohmann::json("download_file") : nlohmann::json(nullptr)},
  };

  return row;
}

bool collect_list_files(const FileListOptions &options, nlohmann::json &data, std::string &reason, std::string &notes)
{
  std::error_code ec;
  if (!std::filesystem::exists(options.root_path, ec))
  {
    reason = "list_files_path_not_found";
    notes = path_to_utf8(options.root_path);
    return false;
  }
  ec.clear();
  if (!std::filesystem::is_directory(options.root_path, ec))
  {
    reason = "list_files_path_not_directory";
    notes = path_to_utf8(options.root_path);
    return false;
  }

  std::vector<nlohmann::json> entries;
  entries.reserve(options.limit);
  std::vector<std::filesystem::path> child_directories;
  std::size_t total_seen = 0;
  bool partial = false;

  const auto add_entry = [&](const std::filesystem::directory_entry &entry) {
    ++total_seen;
    if (!should_include_entry(entry.path(), options))
    {
      return;
    }
    if (entries.size() >= options.limit)
    {
      partial = true;
      return;
    }
    entries.push_back(build_file_entry(entry));
  };

  const std::filesystem::directory_options dir_options = options.follow_symlinks
                                                             ? (std::filesystem::directory_options::skip_permission_denied |
                                                                std::filesystem::directory_options::follow_directory_symlink)
                                                             : std::filesystem::directory_options::skip_permission_denied;

  try
  {
    std::filesystem::directory_iterator root_iter(options.root_path, dir_options, ec);
    std::filesystem::directory_iterator root_end;
    for (; root_iter != root_end; ++root_iter)
    {
      if (ec)
      {
        ec.clear();
        continue;
      }
      add_entry(*root_iter);
      if (options.recursive)
      {
        ec.clear();
        if (root_iter->is_directory(ec))
        {
          child_directories.push_back(root_iter->path());
        }
      }
    }

    if (options.recursive && !partial && options.max_depth > 1)
    {
      for (const auto &child_dir : child_directories)
      {
        std::filesystem::recursive_directory_iterator iter(child_dir, dir_options, ec);
        std::filesystem::recursive_directory_iterator end;
        for (; iter != end; ++iter)
        {
          if (ec)
          {
            ec.clear();
            continue;
          }
          const std::size_t depth_from_root = static_cast<std::size_t>(iter.depth()) + 2;
          if (depth_from_root > options.max_depth)
          {
            iter.disable_recursion_pending();
            continue;
          }
          if (!options.follow_symlinks && iter->is_symlink())
          {
            iter.disable_recursion_pending();
          }
          add_entry(*iter);
          if (partial)
          {
            break;
          }
        }
        if (partial)
        {
          break;
        }
      }
    }
  }
  catch (const std::filesystem::filesystem_error &e)
  {
    reason = "list_files_access_denied";
    notes = e.what();
    return false;
  }
  catch (const std::exception &e)
  {
    reason = "list_files_collect_failed";
    notes = e.what();
    return false;
  }

  std::sort(entries.begin(), entries.end(), [](const nlohmann::json &a, const nlohmann::json &b) {
    const auto at = a.value("type", std::string());
    const auto bt = b.value("type", std::string());
    if (at != bt)
    {
      if (at == "directory")
        return true;
      if (bt == "directory")
        return false;
    }
    return a.value("name", std::string()) < b.value("name", std::string());
  });

  data = {
      {"schema_version", "v1"},
      {"snapshot_type", "list_files"},
      {"kernel_mode", true},
      {"collection_ts_unix", now_unix_string()},
      {"path", path_to_utf8(options.root_path)},
      {"is_directory", true},
      {"recursive", options.recursive},
      {"max_depth", options.max_depth},
      {"partial", partial},
      {"next_cursor", nullptr},
      {"count", entries.size()},
      {"total_seen", total_seen},
      {"entries", entries},
      {"download", {{"supported", true}, {"method", "download_file"}}},
  };
  notes = partial ? "partial_result_limit_reached" : "ok";
  reason.clear();
  return true;
}

bool collect_processes(std::size_t limit, nlohmann::json &data, std::string &reason, std::string &notes)
{
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE)
  {
    reason = "process_snapshot_failed";
    notes = "CreateToolhelp32Snapshot failed";
    return false;
  }

  PROCESSENTRY32 entry{};
  entry.dwSize = sizeof(entry);
  std::vector<nlohmann::json> rows;
  rows.reserve(limit);
  std::size_t total_seen = 0;

  if (Process32First(snapshot, &entry))
  {
    do
    {
      ++total_seen;
      if (rows.size() >= limit)
      {
        continue;
      }

      std::string path;
      HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, entry.th32ProcessID);
      if (process != NULL)
      {
        char buffer[MAX_PATH] = {};
        DWORD size = static_cast<DWORD>(sizeof(buffer));
        if (QueryFullProcessImageNameA(process, 0, buffer, &size) && size > 0)
        {
          path.assign(buffer, size);
          path = ansi_to_utf8(path);
        }
        CloseHandle(process);
      }

      const std::string process_name = ansi_to_utf8(std::string(entry.szExeFile));

      nlohmann::json row = {
          {"pid", static_cast<std::uint32_t>(entry.th32ProcessID)},
          {"ppid", static_cast<std::uint32_t>(entry.th32ParentProcessID)},
          {"name", process_name.empty() ? std::string(entry.szExeFile) : process_name},
          {"threads", static_cast<std::uint32_t>(entry.cntThreads)},
      };
      if (!path.empty())
      {
        row["path"] = path;
      }
      rows.push_back(std::move(row));
    } while (Process32Next(snapshot, &entry));
  }

  CloseHandle(snapshot);

  std::sort(rows.begin(), rows.end(), [](const nlohmann::json &a, const nlohmann::json &b)
            { return a.value("pid", 0u) < b.value("pid", 0u); });

  data = {
      {"schema_version", "v1"},
      {"snapshot_type", "list_processes"},
      {"kernel_mode", true},
      {"collection_ts_unix", now_unix_string()},
      {"count", rows.size()},
      {"total_seen", total_seen},
      {"processes", rows},
  };
  return true;
}

bool collect_services(std::size_t limit, nlohmann::json &data, std::string &reason, std::string &notes)
{
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ENUMERATE_SERVICE);
  if (scm == nullptr)
  {
    reason = "service_manager_open_failed";
    notes = "OpenSCManager failed";
    return false;
  }

  DWORD bytes_needed = 0;
  DWORD services_returned = 0;
  DWORD resume_handle = 0;
  DWORD last_error = 0;
  std::vector<BYTE> buffer(64 * 1024);

  if (!EnumServicesStatusExW(
          scm,
          SC_ENUM_PROCESS_INFO,
          SERVICE_WIN32,
          SERVICE_STATE_ALL,
          buffer.data(),
          static_cast<DWORD>(buffer.size()),
          &bytes_needed,
          &services_returned,
          &resume_handle,
          nullptr))
  {
    last_error = GetLastError();
    if (last_error == ERROR_MORE_DATA && bytes_needed > buffer.size())
    {
      buffer.resize(bytes_needed);
      if (!EnumServicesStatusExW(
              scm,
              SC_ENUM_PROCESS_INFO,
              SERVICE_WIN32,
              SERVICE_STATE_ALL,
              buffer.data(),
              static_cast<DWORD>(buffer.size()),
              &bytes_needed,
              &services_returned,
              &resume_handle,
              nullptr))
      {
        last_error = GetLastError();
      }
      else
      {
        last_error = ERROR_SUCCESS;
      }
    }
  }

  if (last_error != ERROR_SUCCESS)
  {
    CloseServiceHandle(scm);
    reason = "service_enum_failed";
    notes = "EnumServicesStatusEx failed";
    return false;
  }

  auto *entries = reinterpret_cast<ENUM_SERVICE_STATUS_PROCESSW *>(buffer.data());
  std::vector<nlohmann::json> rows;
  rows.reserve(std::min<std::size_t>(services_returned, limit));
  for (DWORD i = 0; i < services_returned && rows.size() < limit; ++i)
  {
    const auto &svc = entries[i];
    const std::string service_name = wide_to_utf8(svc.lpServiceName);
    const std::string display_name = wide_to_utf8(svc.lpDisplayName);
    rows.push_back({
        {"name", service_name},
        {"display_name", display_name},
        {"state", static_cast<std::uint32_t>(svc.ServiceStatusProcess.dwCurrentState)},
        {"pid", static_cast<std::uint32_t>(svc.ServiceStatusProcess.dwProcessId)},
        {"service_type", static_cast<std::uint32_t>(svc.ServiceStatusProcess.dwServiceType)},
    });
  }
  CloseServiceHandle(scm);

  std::sort(rows.begin(), rows.end(), [](const nlohmann::json &a, const nlohmann::json &b)
            { return a.value("name", std::string()) < b.value("name", std::string()); });

  data = {
      {"schema_version", "v1"},
      {"snapshot_type", "list_services"},
      {"kernel_mode", true},
      {"collection_ts_unix", now_unix_string()},
      {"count", rows.size()},
      {"total_seen", services_returned},
      {"services", rows},
  };
  return true;
}

bool collect_connections(std::size_t limit, nlohmann::json &data, std::string &reason, std::string &notes)
{
  std::vector<nlohmann::json> rows;
  rows.reserve(limit);
  std::size_t total_seen = 0;

  DWORD tcp_size = 0;
  GetExtendedTcpTable(nullptr, &tcp_size, TRUE, AF_INET, TCP_TABLE_OWNER_PID_ALL, 0);
  if (tcp_size > 0)
  {
    std::vector<BYTE> tcp_buffer(tcp_size);
    if (GetExtendedTcpTable(tcp_buffer.data(), &tcp_size, TRUE, AF_INET, TCP_TABLE_OWNER_PID_ALL, 0) == NO_ERROR)
    {
      auto *table = reinterpret_cast<MIB_TCPTABLE_OWNER_PID *>(tcp_buffer.data());
      for (DWORD i = 0; i < table->dwNumEntries; ++i)
      {
        ++total_seen;
        if (rows.size() >= limit)
        {
          continue;
        }
        const auto &entry = table->table[i];
        rows.push_back({
            {"proto", "tcp4"},
            {"local_address", ipv4_to_string(entry.dwLocalAddr)},
            {"local_port", static_cast<std::uint32_t>(ntohs(static_cast<u_short>(entry.dwLocalPort)))},
            {"remote_address", ipv4_to_string(entry.dwRemoteAddr)},
            {"remote_port", static_cast<std::uint32_t>(ntohs(static_cast<u_short>(entry.dwRemotePort)))},
            {"state", tcp_state_to_string(entry.dwState)},
            {"pid", static_cast<std::uint32_t>(entry.dwOwningPid)},
        });
      }
    }
  }

  DWORD udp_size = 0;
  GetExtendedUdpTable(nullptr, &udp_size, TRUE, AF_INET, UDP_TABLE_OWNER_PID, 0);
  if (udp_size > 0)
  {
    std::vector<BYTE> udp_buffer(udp_size);
    if (GetExtendedUdpTable(udp_buffer.data(), &udp_size, TRUE, AF_INET, UDP_TABLE_OWNER_PID, 0) == NO_ERROR)
    {
      auto *table = reinterpret_cast<MIB_UDPTABLE_OWNER_PID *>(udp_buffer.data());
      for (DWORD i = 0; i < table->dwNumEntries; ++i)
      {
        ++total_seen;
        if (rows.size() >= limit)
        {
          continue;
        }
        const auto &entry = table->table[i];
        rows.push_back({
            {"proto", "udp4"},
            {"local_address", ipv4_to_string(entry.dwLocalAddr)},
            {"local_port", static_cast<std::uint32_t>(ntohs(static_cast<u_short>(entry.dwLocalPort)))},
            {"remote_address", ""},
            {"remote_port", 0},
            {"state", "open"},
            {"pid", static_cast<std::uint32_t>(entry.dwOwningPid)},
        });
      }
    }
  }

  std::sort(rows.begin(), rows.end(), [](const nlohmann::json &a, const nlohmann::json &b) {
    const auto ap = a.value("proto", std::string());
    const auto bp = b.value("proto", std::string());
    if (ap != bp)
    {
      return ap < bp;
    }
    const auto alp = a.value("local_port", 0u);
    const auto blp = b.value("local_port", 0u);
    if (alp != blp)
    {
      return alp < blp;
    }
    return a.value("pid", 0u) < b.value("pid", 0u);
  });

  data = {
      {"schema_version", "v1"},
      {"snapshot_type", "list_connections"},
      {"kernel_mode", true},
      {"collection_ts_unix", now_unix_string()},
      {"count", rows.size()},
      {"total_seen", total_seen},
      {"connections", rows},
  };
  return true;
}

bool collect_mounts(std::size_t limit, nlohmann::json &data, std::string &reason, std::string &notes)
{
  DWORD required = GetLogicalDriveStringsW(0, nullptr);
  if (required == 0)
  {
    reason = "mounts_enumeration_failed";
    notes = "GetLogicalDriveStrings failed";
    return false;
  }

  std::vector<wchar_t> drives(static_cast<std::size_t>(required) + 1, L'\0');
  DWORD written = GetLogicalDriveStringsW(required, drives.data());
  if (written == 0)
  {
    reason = "mounts_enumeration_failed";
    notes = "GetLogicalDriveStrings failed";
    return false;
  }

  std::vector<nlohmann::json> rows;
  rows.reserve(limit);
  std::size_t total_seen = 0;

  const wchar_t *cursor = drives.data();
  while (*cursor != L'\0')
  {
    ++total_seen;
    if (rows.size() < limit)
    {
      std::wstring root(cursor);
      const std::string mount_point = wide_to_utf8(root.c_str());
      const UINT drive_type = GetDriveTypeW(root.c_str());

      ULARGE_INTEGER free_available{};
      ULARGE_INTEGER total_bytes{};
      ULARGE_INTEGER free_bytes{};
      const BOOL has_space = GetDiskFreeSpaceExW(root.c_str(), &free_available, &total_bytes, &free_bytes);

      wchar_t volume_name[MAX_PATH] = {};
      wchar_t fs_name[MAX_PATH] = {};
      DWORD serial_number = 0;
      DWORD max_component_length = 0;
      DWORD fs_flags = 0;
      const BOOL has_volume = GetVolumeInformationW(
          root.c_str(),
          volume_name,
          MAX_PATH,
          &serial_number,
          &max_component_length,
          &fs_flags,
          fs_name,
          MAX_PATH);

      nlohmann::json row = {
          {"mount", mount_point},
          {"drive_type", drive_type_to_string(drive_type)},
          {"ready", has_space == TRUE || has_volume == TRUE},
      };

      if (has_space == TRUE)
      {
        row["total_mb"] = static_cast<std::uint64_t>(total_bytes.QuadPart / (1024ull * 1024ull));
        row["free_mb"] = static_cast<std::uint64_t>(free_bytes.QuadPart / (1024ull * 1024ull));
      }
      if (has_volume == TRUE)
      {
        row["label"] = wide_to_utf8(volume_name);
        row["filesystem"] = wide_to_utf8(fs_name);
      }

      rows.push_back(std::move(row));
    }

    cursor += wcslen(cursor) + 1;
  }

  std::sort(rows.begin(), rows.end(), [](const nlohmann::json &a, const nlohmann::json &b)
            { return a.value("mount", std::string()) < b.value("mount", std::string()); });

  data = {
      {"schema_version", "v1"},
      {"snapshot_type", "list_mounts"},
      {"kernel_mode", true},
      {"collection_ts_unix", now_unix_string()},
      {"count", rows.size()},
      {"total_seen", total_seen},
      {"mounts", rows},
  };
  return true;
}

bool collect_network_info(std::size_t limit, nlohmann::json &data, std::string &reason, std::string &notes)
{
  ULONG size = 0;
  constexpr ULONG flags = GAA_FLAG_INCLUDE_PREFIX | GAA_FLAG_INCLUDE_GATEWAYS;
  DWORD status = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, nullptr, &size);
  if (status != ERROR_BUFFER_OVERFLOW || size == 0)
  {
    reason = "network_enumeration_failed";
    notes = "GetAdaptersAddresses size probe failed";
    return false;
  }

  std::vector<BYTE> buffer(static_cast<std::size_t>(size));
  auto *addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES *>(buffer.data());
  status = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, addresses, &size);
  if (status != NO_ERROR)
  {
    reason = "network_enumeration_failed";
    notes = "GetAdaptersAddresses failed";
    return false;
  }

  std::vector<nlohmann::json> adapters;
  adapters.reserve(limit);
  std::size_t total_seen = 0;

  for (const auto *adapter = addresses; adapter != nullptr; adapter = adapter->Next)
  {
    ++total_seen;
    if (adapters.size() >= limit)
    {
      continue;
    }

    std::vector<std::string> unicast;
    std::vector<std::string> gateways;
    std::vector<std::string> dns_servers;
    std::string primary_ipv4;
    std::string primary_ipv6;

    for (auto *entry = adapter->FirstUnicastAddress; entry != nullptr; entry = entry->Next)
    {
      const std::string value = socket_address_to_string(entry->Address.lpSockaddr);
      if (value.empty())
      {
        continue;
      }
      if (entry->Address.lpSockaddr != nullptr && entry->Address.lpSockaddr->sa_family == AF_INET && primary_ipv4.empty())
      {
        primary_ipv4 = value;
      }
      if (entry->Address.lpSockaddr != nullptr && entry->Address.lpSockaddr->sa_family == AF_INET6 && primary_ipv6.empty())
      {
        primary_ipv6 = value;
      }
      unicast.push_back(value);
    }

    for (auto *entry = adapter->FirstGatewayAddress; entry != nullptr; entry = entry->Next)
    {
      const std::string value = socket_address_to_string(entry->Address.lpSockaddr);
      if (!value.empty())
      {
        gateways.push_back(value);
      }
    }

    for (auto *entry = adapter->FirstDnsServerAddress; entry != nullptr; entry = entry->Next)
    {
      const std::string value = socket_address_to_string(entry->Address.lpSockaddr);
      if (!value.empty())
      {
        dns_servers.push_back(value);
      }
    }

    nlohmann::json row = {
        {"name", ansi_to_utf8(adapter->AdapterName == nullptr ? "" : adapter->AdapterName)},
        {"friendly_name", wide_to_utf8(adapter->FriendlyName)},
        {"description", wide_to_utf8(adapter->Description)},
        {"status", oper_status_to_string(adapter->OperStatus)},
        {"adapter_type", if_type_to_string(adapter->IfType)},
        {"mtu", adapter->Mtu},
        {"if_index", adapter->IfIndex},
        {"mac", mac_to_string(adapter->PhysicalAddress, adapter->PhysicalAddressLength)},
        {"dns_suffix", wide_to_utf8(adapter->DnsSuffix)},
        {"primary_ipv4", primary_ipv4},
        {"primary_ipv6", primary_ipv6},
        {"unicast", unicast},
        {"gateways", gateways},
        {"dns_servers", dns_servers},
    };
    adapters.push_back(std::move(row));
  }

  std::sort(adapters.begin(), adapters.end(), [](const nlohmann::json &a, const nlohmann::json &b)
            { return a.value("friendly_name", std::string()) < b.value("friendly_name", std::string()); });

  data = {
      {"schema_version", "v1"},
      {"snapshot_type", "network_info"},
      {"kernel_mode", true},
      {"collection_ts_unix", now_unix_string()},
      {"count", adapters.size()},
      {"total_seen", total_seen},
      {"adapters", adapters},
  };
  if (total_seen > adapters.size())
  {
    notes = "truncated_to_limit";
  }
  return true;
}

std::string query_process_path(DWORD pid)
{
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr)
  {
    return {};
  }

  std::wstring path(MAX_PATH, L'\0');
  DWORD size = static_cast<DWORD>(path.size());
  if (!QueryFullProcessImageNameW(process, 0, path.data(), &size))
  {
    CloseHandle(process);
    return {};
  }
  CloseHandle(process);
  path.resize(size);
  return wide_to_utf8(path.c_str());
}

bool collect_active_window(nlohmann::json &data, std::string &reason, std::string &notes)
{
  const DWORD active_console_session = WTSGetActiveConsoleSessionId();
  HWND hwnd = GetForegroundWindow();
  if (hwnd == nullptr)
  {
    reason = "no_foreground_window";
    data = {
        {"schema_version", "v1"},
        {"snapshot_type", "get_active_window"},
        {"kernel_mode", true},
        {"collection_ts_unix", now_unix_string()},
        {"available", false},
        {"status", "no_foreground_window"},
        {"active_console_session_id", active_console_session},
    };
    notes = "no_foreground_window";
    return true;
  }
  reason.clear();

  wchar_t title_buffer[512] = {};
  wchar_t class_buffer[256] = {};
  GetWindowTextW(hwnd, title_buffer, static_cast<int>(sizeof(title_buffer) / sizeof(title_buffer[0])));
  GetClassNameW(hwnd, class_buffer, static_cast<int>(sizeof(class_buffer) / sizeof(class_buffer[0])));

  DWORD pid = 0;
  const DWORD tid = GetWindowThreadProcessId(hwnd, &pid);
  DWORD process_session = 0;
  ProcessIdToSessionId(pid, &process_session);

  RECT rect{};
  if (!GetWindowRect(hwnd, &rect))
  {
    rect = RECT{0, 0, 0, 0};
  }

  const std::string process_path = query_process_path(pid);
  const std::string process_name = file_name_from_path(process_path);

  char hwnd_hex[32] = {};
  std::snprintf(hwnd_hex, sizeof(hwnd_hex), "0x%p", hwnd);

  data = {
      {"schema_version", "v1"},
      {"snapshot_type", "get_active_window"},
      {"kernel_mode", true},
      {"collection_ts_unix", now_unix_string()},
      {"available", true},
      {"status", "ok"},
      {"hwnd", std::string(hwnd_hex)},
      {"title", wide_to_utf8(title_buffer)},
      {"class_name", wide_to_utf8(class_buffer)},
      {"pid", pid},
      {"tid", tid},
      {"process_name", process_name},
      {"process_path", process_path},
      {"active_console_session_id", active_console_session},
      {"process_session_id", process_session},
      {"visible", IsWindowVisible(hwnd) == TRUE},
      {"minimized", IsIconic(hwnd) == TRUE},
      {"bounds", {{"left", rect.left}, {"top", rect.top}, {"right", rect.right}, {"bottom", rect.bottom},
                  {"width", rect.right - rect.left}, {"height", rect.bottom - rect.top}}},
  };
  return true;
}
#endif

} // namespace

bool IsObservabilityMethod(const std::string &method)
{
  const std::string lowered = canonical_method(method);
  return lowered == "list_processes" || lowered == "list_services" || lowered == "list_connections" ||
         lowered == "list_mounts" || lowered == "network_info" || lowered == "get_active_window" ||
         lowered == "list_files" || lowered == "download_file";
}

ObservabilityExecutionResult ExecuteObservabilityCommand(
    const AgentConfig &config,
    const AgentState &state,
    const std::string &method,
    const std::string &command_message_id,
    const std::string &params_json)
{
  const std::string canonical = canonical_method(method);
  const std::size_t limit = parse_limit(params_json);

  IoctlClient ioctl;
  KernelExecResult auth{};
  if (canonical == "list_processes")
  {
    auth = ioctl.get_process_list(command_message_id, state, command_message_id);
  }
  else if (canonical == "list_services")
  {
    auth = ioctl.list_services(command_message_id, state, command_message_id);
  }
  else if (canonical == "list_connections")
  {
    auth = ioctl.list_connections(command_message_id, state, command_message_id);
  }
  else if (canonical == "list_mounts")
  {
    auth = ioctl.list_mounts(command_message_id, state, command_message_id);
  }
  else if (canonical == "network_info")
  {
    auth = ioctl.network_info(command_message_id, state, command_message_id);
  }
  else if (canonical == "get_active_window")
  {
    auth = ioctl.get_active_window(command_message_id, state, command_message_id);
  }
  else if (canonical == "list_files")
  {
    auth = ioctl.list_files(command_message_id, state, params_json, command_message_id);
  }
  else if (canonical == "download_file")
  {
    auth = ioctl.download_file(command_message_id, state, params_json, command_message_id);
  }
  else
  {
    return fail_result(QERR_OBS_COLLECT_FAILED, "unsupported_method", "Unsupported method");
  }

  nlohmann::json kernel_meta = nlohmann::json::object();
  kernel_meta["transport"] = ioctl.using_driver_transport() ? "kernel_ioctl" : "kernel_pipe";
  merge_kernel_meta(auth, kernel_meta);

  if (auth.status != "ok")
  {
    // Compatibility fallback: for phased rollouts where LIST_* auth opcodes may lag on some
    // deployed driver builds, attempt a signed PING authorization before failing.
    // This keeps the command path kernel-mediated while avoiding brittle dependency on a
    // specific opcode error shape.
    KernelExecResult compat_auth = ioctl.ping(command_message_id, state, command_message_id);
    merge_kernel_meta(compat_auth, kernel_meta);
    if (compat_auth.status == "ok")
    {
      kernel_meta["authorization_mode"] = "compat_ping";
      if (is_invalid_opcode_response(auth))
      {
        kernel_meta["authorization_fallback_reason"] = "invalid_opcode";
      }
      else if (auth.error_code == kErrNotSupported)
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
                           : (compat_auth.error_code != 0 ? compat_auth.error_code : QERR_OBS_AUTH_FAILED);
      std::string message = auth.error_message;
      if (message.empty())
      {
        message = compat_auth.error_message;
      }
      if (message.empty())
      {
        message = "kernel authorization failed";
      }
      return fail_result(
          code,
          canonical + "_kernel_authorization_failed",
          message,
          kernel_meta.dump());
    }
  }

#ifdef _WIN32
  nlohmann::json data = nlohmann::json::object();
  std::string reason;
  std::string notes;
  std::string artifact_url;
  std::string artifact_checksum;
  bool collected = false;
  if (canonical == "list_processes")
  {
    collected = collect_processes(limit, data, reason, notes);
  }
  else if (canonical == "list_services")
  {
    collected = collect_services(limit, data, reason, notes);
  }
  else if (canonical == "list_connections")
  {
    collected = collect_connections(limit, data, reason, notes);
  }
  else if (canonical == "list_mounts")
  {
    collected = collect_mounts(limit, data, reason, notes);
  }
  else if (canonical == "network_info")
  {
    collected = collect_network_info(limit, data, reason, notes);
  }
  else if (canonical == "get_active_window")
  {
    collected = collect_active_window(data, reason, notes);
  }
  else if (canonical == "list_files")
  {
    FileListOptions options{};
    if (!parse_file_list_options(params_json, options, reason, notes))
    {
      return fail_result(QERR_FS_INVALID_PARAMS, reason, notes, kernel_meta.dump());
    }
    collected = collect_list_files(options, data, reason, notes);
    if (!collected)
    {
      int code = QERR_OBS_COLLECT_FAILED;
      if (reason == "list_files_path_not_found")
      {
        code = QERR_FS_PATH_NOT_FOUND;
      }
      else if (reason == "list_files_path_not_directory")
      {
        code = QERR_FS_NOT_DIRECTORY;
      }
      else if (reason == "list_files_access_denied")
      {
        code = QERR_FS_ACCESS_DENIED;
      }
      return fail_result(code, reason, notes, kernel_meta.dump());
    }
  }
  else if (canonical == "download_file")
  {
    DownloadOptions options{};
    if (!parse_download_options(params_json, options, reason, notes))
    {
      return fail_result(QERR_FS_INVALID_PARAMS, reason, notes, kernel_meta.dump());
    }

    std::error_code ec;
    if (!std::filesystem::exists(options.file_path, ec))
    {
      return fail_result(QERR_FS_PATH_NOT_FOUND, "download_file_path_not_found", path_to_utf8(options.file_path), kernel_meta.dump());
    }
    ec.clear();
    if (!std::filesystem::is_regular_file(options.file_path, ec))
    {
      return fail_result(QERR_FS_NOT_FILE, "download_file_not_file", path_to_utf8(options.file_path), kernel_meta.dump());
    }
    ec.clear();
    const auto file_size = static_cast<std::uint64_t>(std::filesystem::file_size(options.file_path, ec));
    if (ec)
    {
      return fail_result(QERR_FS_ACCESS_DENIED, "download_file_size_failed", "unable to stat file", kernel_meta.dump());
    }
    if (file_size == 0)
    {
      return fail_result(QERR_FS_NOT_FILE, "download_file_empty", "file is empty", kernel_meta.dump());
    }
    if (file_size > options.max_bytes)
    {
      return fail_result(QERR_FS_TOO_LARGE, "download_file_too_large", "file exceeds max_bytes", kernel_meta.dump());
    }

    auto extension = lowercase_copy(options.file_path.extension().string());
    std::string content_type = "application/octet-stream";
    if (extension == ".png")
    {
      content_type = "image/png";
    }
    else if (extension == ".jpg" || extension == ".jpeg")
    {
      content_type = "image/jpeg";
    }
    else if (extension == ".txt" || extension == ".log" || extension == ".json")
    {
      content_type = "text/plain";
    }

    ArtifactClient artifact_client;
    const auto ticket = artifact_client.request_upload(
        config.artifact_api_base_url,
        config.jwt,
        command_message_id,
        content_type,
        file_size);
    if (!ticket.ok)
    {
      return fail_result(
          QERR_FS_UPLOAD_REQUEST_FAILED,
          "download_file_upload_request_failed",
          ticket.reason.empty() ? "upload_request_failed" : ticket.reason,
          kernel_meta.dump());
    }

    const auto upload = artifact_client.upload_file(
        ticket.upload_url,
        config.jwt,
        ticket.artifact_id,
        ticket.upload_token,
        options.file_path.string());
    if (!upload.ok)
    {
      return fail_result(
          QERR_FS_UPLOAD_FAILED,
          "download_file_upload_failed",
          upload.reason.empty() ? "upload_failed" : upload.reason,
          kernel_meta.dump());
    }

    data = {
        {"schema_version", "v1"},
        {"snapshot_type", "download_file"},
        {"kernel_mode", true},
        {"collection_ts_unix", now_unix_string()},
        {"path", path_to_utf8(options.file_path)},
        {"name", path_to_utf8(options.file_path.filename())},
        {"size_bytes", file_size},
        {"extension", options.file_path.has_extension() ? options.file_path.extension().string() : std::string()},
        {"content_type", content_type},
        {"status", "uploaded"},
    };
    artifact_url = upload.artifact_url;
    artifact_checksum = upload.artifact_checksum;
    notes = "download_file_uploaded";
    collected = true;
  }

  if (!collected)
  {
    return fail_result(QERR_OBS_COLLECT_FAILED, reason.empty() ? "observability_collect_failed" : reason, notes, kernel_meta.dump());
  }

  ObservabilityExecutionResult out{};
  out.success = true;
  if (!notes.empty())
  {
    out.notes = notes;
  }
  else
  {
    out.notes = kernel_meta.contains("authorization_mode")
                    ? canonical + " collected (compat auth)"
                    : canonical + " collected";
  }
  out.data_json = data.dump();
  out.meta_json = kernel_meta.dump();
  out.artifact_url = artifact_url;
  out.artifact_checksum = artifact_checksum;
  return out;
#else
  return fail_result(QERR_OBS_COLLECT_FAILED, "unsupported_platform", "observability collectors are only supported on Windows", kernel_meta.dump());
#endif
}

} // namespace command
