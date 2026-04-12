#include "collect_system_info_codec.hpp"

#include <nlohmann/json.hpp>

#include <cstring>
#include <string>
#include <cstdint>
#include <vector>
#include <sstream>
#include <iomanip>
#ifdef _WIN32
#include <windows.h>
#include <iphlpapi.h>
#include <intrin.h>
#endif

namespace
{

std::string bounded_cstr(const char *value, size_t cap)
{
  size_t len = 0;
  while (len < cap && value[len] != '\0')
  {
    ++len;
  }
  return std::string(value, len);
}

nlohmann::json collect_info_identity_sentinel()
{
  return {
      {"hostname", nullptr},
      {"computer_name", nullptr},
      {"machine_guid", nullptr},
      {"smbios_uuid", nullptr},
      {"system_serial", nullptr},
      {"baseboard_serial", nullptr},
      {"bios_vendor", nullptr},
  };
}

nlohmann::json collect_info_os_sentinel()
{
  return {
      {"product_name", nullptr},
      {"version", nullptr},
      {"build", nullptr},
      {"ubr", nullptr},
      {"arch", nullptr},
  };
}

nlohmann::json collect_info_hardware_sentinel()
{
  return {
      {"cpu_model", nullptr},
      {"cpu_logical_cores", nullptr},
      {"ram_total_mb", nullptr},
      {"ram_available_mb", nullptr},
  };
}

nlohmann::json collect_info_runtime_sentinel()
{
  return {
      {"uptime_sec", nullptr},
      {"policy_hash", nullptr},
      {"ioctl_contract_version", nullptr},
  };
}

nlohmann::json collect_info_storage_sentinel()
{
  return {
      {"system_drive", nullptr},
      {"system_drive_total_mb", nullptr},
      {"system_drive_free_mb", nullptr},
      {"system_drive_fs", nullptr},
      {"boot_volume", nullptr},
      {"boot_volume_total_mb", nullptr},
      {"boot_volume_free_mb", nullptr},
      {"disk_count", nullptr},
      {"primary_disk_model", nullptr},
      {"primary_disk_serial", nullptr},
      {"primary_disk_bus_type", nullptr},
      {"primary_disk_media_type", nullptr},
      {"primary_disk_health", nullptr},
      {"bitlocker_enabled", nullptr},
      {"bitlocker_protection_status", nullptr},
  };
}

nlohmann::json collect_info_network_sentinel()
{
  return {
      {"primary_adapter_name", nullptr},
      {"primary_adapter_desc", nullptr},
      {"primary_adapter_type", nullptr},
      {"primary_ipv4", nullptr},
      {"primary_ipv6", nullptr},
      {"primary_mac", nullptr},
      {"default_gateway_ipv4", nullptr},
      {"default_gateway_ipv6", nullptr},
      {"dns_servers", nlohmann::json::array()},
      {"dhcp_enabled", nullptr},
      {"dhcp_server", nullptr},
      {"link_speed_mbps", nullptr},
      {"wifi_ssid", nullptr},
      {"wifi_bssid", nullptr},
      {"network_profile", nullptr},
      {"internet_reachable", nullptr},
  };
}

nlohmann::json collect_info_security_sentinel()
{
  return {
      {"dse_enabled", nullptr},
      {"secure_boot", nullptr},
      {"code_integrity", nullptr},
      {"memory_integrity", nullptr},
      {"test_signing", nullptr},
      {"debug_mode", nullptr},
      {"hypervisor_present", nullptr},
      {"vbs_enabled", nullptr},
      {"hvci_enabled", nullptr},
      {"credential_guard", nullptr},
      {"device_guard", nullptr},
      {"tpm_present", nullptr},
      {"tpm_ready", nullptr},
      {"tpm_version", nullptr},
      {"bitlocker_status", nullptr},
      {"firewall_enabled", nullptr},
      {"defender_enabled", nullptr},
      {"defender_signature_version", nullptr},
      {"last_update_state", nullptr},
      {"attestation_capable", nullptr},
      {"tamper_check_capable", nullptr},
      {"loaded_driver_count", nullptr},
  };
}

bool decode_collect_info_binary_payload(const QuoodleIoctlResponse &resp, QuoodleCollectInfoBinaryV1 &payload)
{
  if (resp.result_length < sizeof(payload.magic) + sizeof(payload.version))
  {
    return false;
  }
  std::memset(&payload, 0, sizeof(payload));
  const size_t copy_len = (resp.result_length < sizeof(payload))
                              ? static_cast<size_t>(resp.result_length)
                              : sizeof(payload);
  std::memcpy(&payload, resp.result_json, copy_len);
  return payload.magic == QUOODLE_COLLECT_INFO_BINARY_MAGIC &&
         payload.version == QUOODLE_COLLECT_INFO_BINARY_VERSION;
}

void collect_info_set_string_or_null(
    nlohmann::json &obj,
    const char *key,
    bool include_section,
    bool has_field,
    const char *value,
    size_t cap)
{
  if (!include_section || !has_field)
  {
    obj[key] = nullptr;
    return;
  }
  const std::string bounded = bounded_cstr(value, cap);
  obj[key] = bounded.empty() ? nlohmann::json(nullptr) : nlohmann::json(bounded);
}

void collect_info_set_uint_or_null(
    nlohmann::json &obj,
    const char *key,
    bool include_section,
    bool has_field,
    std::uint64_t value)
{
  if (!include_section || !has_field)
  {
    obj[key] = nullptr;
    return;
  }
  obj[key] = value;
}

void collect_info_set_bool_or_null(
    nlohmann::json &obj,
    const char *key,
    bool include_section,
    bool has_field,
    bool value)
{
  if (!include_section || !has_field)
  {
    obj[key] = nullptr;
    return;
  }
  obj[key] = value;
}

nlohmann::json build_collect_info_identity_json(
    const QuoodleCollectInfoBinaryV1 &payload,
    bool include_identity,
    std::uint32_t present_mask)
{
  nlohmann::json identity = collect_info_identity_sentinel();
  collect_info_set_string_or_null(identity, "hostname", include_identity, (present_mask & QUOODLE_COLLECT_PRESENT_HOSTNAME) != 0, payload.hostname, sizeof(payload.hostname));
  collect_info_set_string_or_null(identity, "computer_name", include_identity, (present_mask & QUOODLE_COLLECT_PRESENT_COMPUTER_NAME) != 0, payload.computer_name, sizeof(payload.computer_name));
  collect_info_set_string_or_null(identity, "machine_guid", include_identity, (present_mask & QUOODLE_COLLECT_PRESENT_MACHINE_GUID) != 0, payload.machine_guid, sizeof(payload.machine_guid));
  collect_info_set_string_or_null(identity, "smbios_uuid", include_identity, (present_mask & QUOODLE_COLLECT_PRESENT_FIRMWARE_SMBIOS_UUID) != 0, payload.smbios_uuid, sizeof(payload.smbios_uuid));
  collect_info_set_string_or_null(identity, "system_serial", include_identity, (present_mask & QUOODLE_COLLECT_PRESENT_FIRMWARE_SYSTEM_SERIAL) != 0, payload.system_serial, sizeof(payload.system_serial));
  collect_info_set_string_or_null(identity, "baseboard_serial", include_identity, (present_mask & QUOODLE_COLLECT_PRESENT_FIRMWARE_BASEBOARD_SERIAL) != 0, payload.baseboard_serial, sizeof(payload.baseboard_serial));
  collect_info_set_string_or_null(identity, "bios_vendor", include_identity, (present_mask & QUOODLE_COLLECT_PRESENT_FIRMWARE_BIOS_VENDOR) != 0, payload.bios_vendor, sizeof(payload.bios_vendor));
  return identity;
}

nlohmann::json build_collect_info_os_json(
    const QuoodleCollectInfoBinaryV1 &payload,
    bool include_os,
    std::uint32_t present_mask)
{
  nlohmann::json os = collect_info_os_sentinel();
  collect_info_set_string_or_null(os, "product_name", include_os, (present_mask & QUOODLE_COLLECT_PRESENT_OS_PRODUCT_NAME) != 0, payload.os_product_name, sizeof(payload.os_product_name));
  collect_info_set_string_or_null(os, "version", include_os, (present_mask & QUOODLE_COLLECT_PRESENT_OS_VERSION) != 0, payload.os_version, sizeof(payload.os_version));
  collect_info_set_string_or_null(os, "build", include_os, (present_mask & QUOODLE_COLLECT_PRESENT_OS_BUILD) != 0, payload.os_build, sizeof(payload.os_build));
  collect_info_set_uint_or_null(os, "ubr", include_os, (present_mask & QUOODLE_COLLECT_PRESENT_OS_UBR) != 0, payload.os_ubr);
  collect_info_set_string_or_null(os, "arch", include_os, (present_mask & QUOODLE_COLLECT_PRESENT_ARCH) != 0, payload.arch, sizeof(payload.arch));
  return os;
}

nlohmann::json build_collect_info_hardware_json(
    const QuoodleCollectInfoBinaryV1 &payload,
    bool include_hardware,
    std::uint32_t present_mask)
{
  nlohmann::json hardware = collect_info_hardware_sentinel();
  collect_info_set_string_or_null(hardware, "cpu_model", include_hardware, (present_mask & QUOODLE_COLLECT_PRESENT_CPU_MODEL) != 0, payload.cpu_model, sizeof(payload.cpu_model));
  collect_info_set_uint_or_null(hardware, "cpu_logical_cores", include_hardware, (present_mask & QUOODLE_COLLECT_PRESENT_CPU_LOGICAL_CORES) != 0, payload.cpu_logical_cores);
  collect_info_set_uint_or_null(hardware, "ram_total_mb", include_hardware, (present_mask & QUOODLE_COLLECT_PRESENT_RAM_TOTAL_MB) != 0, payload.ram_total_mb);
  collect_info_set_uint_or_null(hardware, "ram_available_mb", include_hardware, (present_mask & QUOODLE_COLLECT_PRESENT_RAM_AVAILABLE_MB) != 0, payload.ram_available_mb);
  return hardware;
}

nlohmann::json build_collect_info_runtime_json(
    const QuoodleCollectInfoBinaryV1 &payload,
    bool include_runtime,
    std::uint32_t present_mask)
{
  nlohmann::json runtime = collect_info_runtime_sentinel();
  collect_info_set_uint_or_null(runtime, "uptime_sec", include_runtime, (present_mask & QUOODLE_COLLECT_PRESENT_UPTIME_SEC) != 0, payload.uptime_sec);
  collect_info_set_string_or_null(runtime, "policy_hash", include_runtime, (present_mask & QUOODLE_COLLECT_PRESENT_POLICY_HASH) != 0, payload.policy_hash, sizeof(payload.policy_hash));
  collect_info_set_uint_or_null(runtime, "ioctl_contract_version", include_runtime, (present_mask & QUOODLE_COLLECT_PRESENT_IOCTL_CONTRACT_VERSION) != 0, payload.ioctl_contract_version);
  return runtime;
}

nlohmann::json build_collect_info_security_json(
    const QuoodleCollectInfoBinaryV1 &payload,
    bool include_security,
    std::uint32_t present_mask,
    std::uint32_t flags)
{
  nlohmann::json security = collect_info_security_sentinel();
  collect_info_set_bool_or_null(
      security,
      "dse_enabled",
      include_security,
      (present_mask & QUOODLE_COLLECT_PRESENT_SECURITY_DSE_ENABLED) != 0,
      (flags & QUOODLE_COLLECT_FLAG_SECURITY_DSE_ENABLED_TRUE) != 0);
  collect_info_set_bool_or_null(
      security,
      "code_integrity",
      include_security,
      (present_mask & QUOODLE_COLLECT_PRESENT_SECURITY_CODE_INTEGRITY) != 0,
      (flags & QUOODLE_COLLECT_FLAG_SECURITY_CODE_INTEGRITY_TRUE) != 0);
  collect_info_set_bool_or_null(
      security,
      "test_signing",
      include_security,
      (present_mask & QUOODLE_COLLECT_PRESENT_SECURITY_TEST_SIGNING) != 0,
      (flags & QUOODLE_COLLECT_FLAG_SECURITY_TEST_SIGNING_TRUE) != 0);
  collect_info_set_bool_or_null(
      security,
      "hvci_enabled",
      include_security,
      (present_mask & QUOODLE_COLLECT_PRESENT_SECURITY_HVCI_ENABLED) != 0,
      (flags & QUOODLE_COLLECT_FLAG_SECURITY_HVCI_ENABLED_TRUE) != 0);
  collect_info_set_bool_or_null(
      security,
      "vbs_enabled",
      include_security,
      (present_mask & QUOODLE_COLLECT_PRESENT_SECURITY_VBS_ENABLED) != 0,
      (flags & QUOODLE_COLLECT_FLAG_SECURITY_VBS_ENABLED_TRUE) != 0);
  collect_info_set_bool_or_null(
      security,
      "memory_integrity",
      include_security,
      (present_mask & QUOODLE_COLLECT_PRESENT_SECURITY_MEMORY_INTEGRITY) != 0,
      (flags & QUOODLE_COLLECT_FLAG_SECURITY_MEMORY_INTEGRITY_TRUE) != 0);
  collect_info_set_uint_or_null(
      security,
      "loaded_driver_count",
      include_security,
      (present_mask & QUOODLE_COLLECT_PRESENT_SECURITY_LOADED_DRIVER_COUNT) != 0,
      payload.loaded_driver_count);
  return security;
}

#ifdef _WIN32
bool query_available_ram_mb(std::uint64_t &out_available_mb)
{
  MEMORYSTATUSEX mem_status{};
  mem_status.dwLength = sizeof(mem_status);
  if (!GlobalMemoryStatusEx(&mem_status))
  {
    return false;
  }
  out_available_mb = static_cast<std::uint64_t>(mem_status.ullAvailPhys / (1024ULL * 1024ULL));
  return true;
}

bool is_nonzero_ipv4(const char *ip)
{
  return ip != nullptr && ip[0] != '\0' && std::strcmp(ip, "0.0.0.0") != 0;
}

std::string format_mac_address(const BYTE *addr, UINT len)
{
  if (!addr || len == 0)
  {
    return {};
  }
  std::ostringstream oss;
  oss << std::hex << std::setfill('0');
  for (UINT i = 0; i < len; ++i)
  {
    if (i > 0)
    {
      oss << ":";
    }
    oss << std::setw(2) << static_cast<unsigned int>(addr[i]);
  }
  return oss.str();
}

const char *adapter_type_label(UINT adapter_type)
{
  switch (adapter_type)
  {
  case MIB_IF_TYPE_ETHERNET:
    return "ethernet";
  case IF_TYPE_IEEE80211:
    return "wifi";
  case MIB_IF_TYPE_PPP:
    return "ppp";
  case MIB_IF_TYPE_LOOPBACK:
    return "loopback";
  default:
    return "other";
  }
}

bool enrich_storage_section(nlohmann::json &storage)
{
  bool populated = false;
  char windows_dir[MAX_PATH] = {};
  if (!GetWindowsDirectoryA(windows_dir, MAX_PATH))
  {
    return false;
  }
  if (windows_dir[0] == '\0' || windows_dir[1] != ':')
  {
    return false;
  }

  const std::string system_drive = std::string(1, windows_dir[0]) + ":";
  const std::string root_path = system_drive + "\\";

  storage["system_drive"] = system_drive;
  storage["boot_volume"] = system_drive;
  populated = true;

  ULARGE_INTEGER free_bytes_available = {};
  ULARGE_INTEGER total_bytes = {};
  ULARGE_INTEGER total_free_bytes = {};
  if (GetDiskFreeSpaceExA(root_path.c_str(), &free_bytes_available, &total_bytes, &total_free_bytes))
  {
    const std::uint64_t total_mb = static_cast<std::uint64_t>(total_bytes.QuadPart / (1024ULL * 1024ULL));
    const std::uint64_t free_mb = static_cast<std::uint64_t>(total_free_bytes.QuadPart / (1024ULL * 1024ULL));
    storage["system_drive_total_mb"] = total_mb;
    storage["system_drive_free_mb"] = free_mb;
    storage["boot_volume_total_mb"] = total_mb;
    storage["boot_volume_free_mb"] = free_mb;
    populated = true;
  }

  char fs_name[MAX_PATH] = {};
  if (GetVolumeInformationA(root_path.c_str(), nullptr, 0, nullptr, nullptr, nullptr, fs_name, MAX_PATH) && fs_name[0] != '\0')
  {
    storage["system_drive_fs"] = std::string(fs_name);
    populated = true;
  }

  const DWORD logical_drives = GetLogicalDrives();
  if (logical_drives != 0)
  {
    std::uint32_t count = 0;
    DWORD bits = logical_drives;
    while (bits != 0)
    {
      count += (bits & 1U);
      bits >>= 1U;
    }
    storage["disk_count"] = count;
    populated = true;
  }

  return populated;
}

bool enrich_network_section(nlohmann::json &network)
{
  bool populated = false;
  ULONG adapters_len = 0;
  DWORD rc = GetAdaptersInfo(nullptr, &adapters_len);
  if (rc != ERROR_BUFFER_OVERFLOW || adapters_len == 0)
  {
    return false;
  }

  std::vector<BYTE> adapter_buf(adapters_len);
  auto *adapters = reinterpret_cast<PIP_ADAPTER_INFO>(adapter_buf.data());
  rc = GetAdaptersInfo(adapters, &adapters_len);
  if (rc != NO_ERROR)
  {
    return false;
  }

  PIP_ADAPTER_INFO selected = nullptr;
  for (PIP_ADAPTER_INFO cur = adapters; cur != nullptr; cur = cur->Next)
  {
    if (!selected)
    {
      selected = cur;
    }
    if (is_nonzero_ipv4(cur->IpAddressList.IpAddress.String))
    {
      selected = cur;
      break;
    }
  }

  if (!selected)
  {
    return false;
  }

  if (selected->AdapterName[0] != '\0')
  {
    network["primary_adapter_name"] = std::string(selected->AdapterName);
    populated = true;
  }
  if (selected->Description[0] != '\0')
  {
    network["primary_adapter_desc"] = std::string(selected->Description);
    populated = true;
  }
  network["primary_adapter_type"] = std::string(adapter_type_label(selected->Type));
  populated = true;

  if (is_nonzero_ipv4(selected->IpAddressList.IpAddress.String))
  {
    network["primary_ipv4"] = std::string(selected->IpAddressList.IpAddress.String);
    populated = true;
  }
  if (is_nonzero_ipv4(selected->GatewayList.IpAddress.String))
  {
    network["default_gateway_ipv4"] = std::string(selected->GatewayList.IpAddress.String);
    populated = true;
  }

  network["dhcp_enabled"] = selected->DhcpEnabled != 0;
  populated = true;
  if (is_nonzero_ipv4(selected->DhcpServer.IpAddress.String))
  {
    network["dhcp_server"] = std::string(selected->DhcpServer.IpAddress.String);
    populated = true;
  }

  const std::string mac = format_mac_address(selected->Address, selected->AddressLength);
  if (!mac.empty())
  {
    network["primary_mac"] = mac;
    populated = true;
  }

  MIB_IFROW if_row = {};
  if_row.dwIndex = selected->Index;
  if (GetIfEntry(&if_row) == NO_ERROR && if_row.dwSpeed > 0)
  {
    network["link_speed_mbps"] = static_cast<std::uint64_t>(if_row.dwSpeed / 1000000U);
    populated = true;
  }

  ULONG fixed_len = 0;
  if (GetNetworkParams(nullptr, &fixed_len) == ERROR_BUFFER_OVERFLOW && fixed_len > 0)
  {
    std::vector<BYTE> fixed_buf(fixed_len);
    auto *fixed_info = reinterpret_cast<PFIXED_INFO>(fixed_buf.data());
    if (GetNetworkParams(fixed_info, &fixed_len) == NO_ERROR)
    {
      nlohmann::json dns = nlohmann::json::array();
      for (IP_ADDR_STRING *cur = &fixed_info->DnsServerList; cur != nullptr; cur = cur->Next)
      {
        if (is_nonzero_ipv4(cur->IpAddress.String))
        {
          dns.push_back(std::string(cur->IpAddress.String));
        }
      }
      if (!dns.empty())
      {
        network["dns_servers"] = std::move(dns);
        populated = true;
      }
    }
  }

  return populated;
}

bool query_reg_dword(HKEY root, const char *path, const char *name, DWORD &out_value)
{
  DWORD value = 0;
  DWORD value_size = sizeof(value);
  DWORD value_type = 0;
  const LONG status = RegGetValueA(root, path, name, RRF_RT_REG_DWORD, &value_type, &value, &value_size);
  if (status != ERROR_SUCCESS)
  {
    return false;
  }
  out_value = value;
  return true;
}

bool enrich_security_section(nlohmann::json &security)
{
  bool populated = false;

  DWORD secure_boot = 0;
  if (query_reg_dword(HKEY_LOCAL_MACHINE,
                      "SYSTEM\\CurrentControlSet\\Control\\SecureBoot\\State",
                      "UEFISecureBootEnabled",
                      secure_boot))
  {
    security["secure_boot"] = secure_boot != 0;
    populated = true;
  }

#if defined(_M_X64) || defined(_M_IX86) || defined(_M_AMD64)
  int cpu_info[4] = {0, 0, 0, 0};
  __cpuid(cpu_info, 1);
  security["hypervisor_present"] = ((cpu_info[2] & (1 << 31)) != 0);
  populated = true;
#else
  security["hypervisor_present"] = false;
  populated = true;
#endif

  return populated;
}
#endif

void remove_collection_failure(
    nlohmann::json &out,
    const std::string &field,
    const std::string &reason)
{
  if (!out.contains("collection_failures") || !out["collection_failures"].is_array())
  {
    return;
  }

  nlohmann::json filtered_failures = nlohmann::json::array();
  for (const auto &entry : out["collection_failures"])
  {
    if (!entry.is_object())
    {
      filtered_failures.push_back(entry);
      continue;
    }
    if (entry.value("field", "") == field && entry.value("reason", "") == reason)
    {
      continue;
    }
    filtered_failures.push_back(entry);
  }
  out["collection_failures"] = std::move(filtered_failures);
}

void enrich_collect_info_with_local_fallbacks(nlohmann::json &out)
{
  if (!out.is_object())
  {
    return;
  }
  nlohmann::json *hardware = (out.contains("hardware") && out["hardware"].is_object()) ? &out["hardware"] : nullptr;
  nlohmann::json *storage = (out.contains("storage") && out["storage"].is_object()) ? &out["storage"] : nullptr;
  nlohmann::json *network = (out.contains("network") && out["network"].is_object()) ? &out["network"] : nullptr;
  nlohmann::json *security = (out.contains("security") && out["security"].is_object()) ? &out["security"] : nullptr;

#ifdef _WIN32
  if (hardware)
  {
    const bool missing_available_ram =
        !hardware->contains("ram_available_mb") || (*hardware)["ram_available_mb"].is_null();
    if (missing_available_ram)
    {
      std::uint64_t available_mb = 0;
      if (query_available_ram_mb(available_mb))
      {
        (*hardware)["ram_available_mb"] = available_mb;
      }
    }
  }

  if (storage)
  {
    const bool has_storage_data = enrich_storage_section(*storage);
    if (has_storage_data)
    {
      remove_collection_failure(out, "storage", "not_implemented");
    }
  }

  if (network)
  {
    const bool has_network_data = enrich_network_section(*network);
    if (has_network_data)
    {
      remove_collection_failure(out, "network", "not_implemented");
    }
  }

  if (security)
  {
    const bool has_security_data = enrich_security_section(*security);
    if (has_security_data)
    {
      remove_collection_failure(out, "security", "not_implemented");
    }
  }
#endif

  const bool has_real_available_ram =
      hardware && hardware->contains("ram_available_mb") && !(*hardware)["ram_available_mb"].is_null();
  if (has_real_available_ram)
  {
    remove_collection_failure(out, "hardware.ram_available_mb", "not_collectable");
  }
}

void prune_null_values(nlohmann::json &node)
{
  if (node.is_object())
  {
    for (auto it = node.begin(); it != node.end();)
    {
      prune_null_values(it.value());
      if (it.value().is_null())
      {
        it = node.erase(it);
      }
      else
      {
        ++it;
      }
    }
    return;
  }

  if (node.is_array())
  {
    for (auto &item : node)
    {
      prune_null_values(item);
    }

    for (auto it = node.begin(); it != node.end();)
    {
      if (it->is_null())
      {
        it = node.erase(it);
      }
      else
      {
        ++it;
      }
    }
  }
}

nlohmann::json build_collect_info_included_fields(std::uint32_t sections_mask)
{
  nlohmann::json included_fields = nlohmann::json::array();
  if ((sections_mask & QUOODLE_COLLECT_SECTION_IDENTITY) != 0) included_fields.push_back("identity");
  if ((sections_mask & QUOODLE_COLLECT_SECTION_OS) != 0) included_fields.push_back("os");
  if ((sections_mask & QUOODLE_COLLECT_SECTION_HARDWARE) != 0) included_fields.push_back("hardware");
  if ((sections_mask & QUOODLE_COLLECT_SECTION_RUNTIME) != 0) included_fields.push_back("runtime");
  if ((sections_mask & QUOODLE_COLLECT_SECTION_STORAGE) != 0) included_fields.push_back("storage");
  if ((sections_mask & QUOODLE_COLLECT_SECTION_NETWORK) != 0) included_fields.push_back("network");
  if ((sections_mask & QUOODLE_COLLECT_SECTION_SECURITY) != 0) included_fields.push_back("security");
  return included_fields;
}

nlohmann::json build_collect_info_collection_failures(
    std::uint32_t sections_mask,
    std::uint32_t flags)
{
  const bool include_hardware = (sections_mask & QUOODLE_COLLECT_SECTION_HARDWARE) != 0;
  const bool include_storage = (sections_mask & QUOODLE_COLLECT_SECTION_STORAGE) != 0;
  const bool include_network = (sections_mask & QUOODLE_COLLECT_SECTION_NETWORK) != 0;
  const bool include_security = (sections_mask & QUOODLE_COLLECT_SECTION_SECURITY) != 0;
  nlohmann::json collection_failures = nlohmann::json::array();

  if (include_hardware && (flags & QUOODLE_COLLECT_FLAG_RAM_AVAILABLE_NOT_COLLECTABLE))
    collection_failures.push_back({{"field", "hardware.ram_available_mb"}, {"reason", "not_collectable"}});
  if (include_storage && (flags & QUOODLE_COLLECT_FLAG_STORAGE_NOT_IMPLEMENTED))
    collection_failures.push_back({{"field", "storage"}, {"reason", "not_implemented"}});
  if (include_network && (flags & QUOODLE_COLLECT_FLAG_NETWORK_NOT_IMPLEMENTED))
    collection_failures.push_back({{"field", "network"}, {"reason", "not_implemented"}});
  if (include_security && (flags & QUOODLE_COLLECT_FLAG_SECURITY_NOT_IMPLEMENTED))
    collection_failures.push_back({{"field", "security"}, {"reason", "not_implemented"}});

  return collection_failures;
}

nlohmann::json translate_collect_info_binary_payload(const QuoodleCollectInfoBinaryV1 &payload)
{
  const std::uint32_t sections_mask = payload.sections_mask;
  const std::uint32_t present_mask = payload.fields_present_mask;
  const bool include_identity = (sections_mask & QUOODLE_COLLECT_SECTION_IDENTITY) != 0;
  const bool include_os = (sections_mask & QUOODLE_COLLECT_SECTION_OS) != 0;
  const bool include_hardware = (sections_mask & QUOODLE_COLLECT_SECTION_HARDWARE) != 0;
  const bool include_runtime = (sections_mask & QUOODLE_COLLECT_SECTION_RUNTIME) != 0;
  const bool include_storage = (sections_mask & QUOODLE_COLLECT_SECTION_STORAGE) != 0;
  const bool include_network = (sections_mask & QUOODLE_COLLECT_SECTION_NETWORK) != 0;
  const bool include_security = (sections_mask & QUOODLE_COLLECT_SECTION_SECURITY) != 0;

  nlohmann::json out = {
      {"schema_version", "v2"},
      {"snapshot_type", "collect_system_info"},
      {"kernel_mode", true},
      {"collection_ts_unix", payload.collection_ts_unix},
      {"included_fields", build_collect_info_included_fields(sections_mask)},
      {"masked_fields", nlohmann::json::array()},
      {"collection_failures", build_collect_info_collection_failures(sections_mask, payload.flags)},
      {"identity", build_collect_info_identity_json(payload, include_identity, present_mask)},
      {"os", build_collect_info_os_json(payload, include_os, present_mask)},
      {"hardware", build_collect_info_hardware_json(payload, include_hardware, present_mask)},
      {"runtime", build_collect_info_runtime_json(payload, include_runtime, present_mask)},
  };
  if (include_storage)
  {
    out["storage"] = collect_info_storage_sentinel();
  }
  if (include_network)
  {
    out["network"] = collect_info_network_sentinel();
  }
  if (include_security)
  {
    out["security"] = build_collect_info_security_json(payload, include_security, present_mask, payload.flags);
  }
  enrich_collect_info_with_local_fallbacks(out);
  prune_null_values(out);
  return out;
}

} // namespace

namespace kernel::opcodes
{

bool TryTranslateCollectSystemInfoBinaryResult(
    const QuoodleIoctlResponse &response,
    std::string &out_json)
{
  QuoodleCollectInfoBinaryV1 payload{};
  if (!decode_collect_info_binary_payload(response, payload))
  {
    return false;
  }
  out_json = translate_collect_info_binary_payload(payload).dump();
  return true;
}

} // namespace kernel::opcodes
