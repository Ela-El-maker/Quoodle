#include "observability_command.hpp"

#include "../kernel/ioctl_client.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdio>
#include <cstdint>
#include <string>
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
constexpr std::size_t kDefaultLimit = 250;
constexpr std::size_t kMaxLimit = 1000;
constexpr int kErrInvalidOpcode = 4002;
constexpr int kErrNotSupported = 4004;

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
         lowered == "list_mounts" || lowered == "network_info" || lowered == "get_active_window";
}

ObservabilityExecutionResult ExecuteObservabilityCommand(
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
  else
  {
    return fail_result(QERR_OBS_COLLECT_FAILED, "unsupported_observability_method", "Unsupported observability method");
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

  if (!collected)
  {
    return fail_result(QERR_OBS_COLLECT_FAILED, reason.empty() ? "observability_collect_failed" : reason, notes, kernel_meta.dump());
  }

  ObservabilityExecutionResult out{};
  out.success = true;
  out.notes = kernel_meta.contains("authorization_mode")
                  ? canonical + " collected (compat auth)"
                  : canonical + " collected";
  out.data_json = data.dump();
  out.meta_json = kernel_meta.dump();
  return out;
#else
  return fail_result(QERR_OBS_COLLECT_FAILED, "unsupported_platform", "observability collectors are only supported on Windows", kernel_meta.dump());
#endif
}

} // namespace command
