#include "collect_system_info_codec.hpp"

#include <nlohmann/json.hpp>

#include <cstring>
#include <string>
#include <cstdint>

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
  };
}

bool decode_collect_info_binary_payload(const QuoodleIoctlResponse &resp, QuoodleCollectInfoBinaryV1 &payload)
{
  if (resp.result_length < sizeof(QuoodleCollectInfoBinaryV1))
  {
    return false;
  }
  std::memcpy(&payload, resp.result_json, sizeof(payload));
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

nlohmann::json build_collect_info_identity_json(
    const QuoodleCollectInfoBinaryV1 &payload,
    bool include_identity,
    std::uint32_t present_mask)
{
  nlohmann::json identity = collect_info_identity_sentinel();
  collect_info_set_string_or_null(identity, "hostname", include_identity, (present_mask & QUOODLE_COLLECT_PRESENT_HOSTNAME) != 0, payload.hostname, sizeof(payload.hostname));
  collect_info_set_string_or_null(identity, "computer_name", include_identity, (present_mask & QUOODLE_COLLECT_PRESENT_COMPUTER_NAME) != 0, payload.computer_name, sizeof(payload.computer_name));
  collect_info_set_string_or_null(identity, "machine_guid", include_identity, (present_mask & QUOODLE_COLLECT_PRESENT_MACHINE_GUID) != 0, payload.machine_guid, sizeof(payload.machine_guid));
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
      {"storage", collect_info_storage_sentinel()},
      {"network", collect_info_network_sentinel()},
      {"security", collect_info_security_sentinel()},
  };
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
