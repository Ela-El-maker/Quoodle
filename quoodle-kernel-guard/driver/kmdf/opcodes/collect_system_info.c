#include <ntstrsafe.h>

#include "kmdf_opcode_handlers.h"
#include "kmdf_opcode_common.h"

VOID QuoodleOpcodeHandleCollectSystemInfo(_Out_ QUOODLE_IOCTL_RESPONSE* resp, _In_opt_ const CHAR* policy_hash) {
  const WCHAR* os_key = L"\\Registry\\Machine\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";
  CHAR os_build[64];
  CHAR os_version[64];
  CHAR os_product_name[128];
  CHAR arch_value[32];
  CHAR cpu_model[96];
  CHAR policy_hash_value[QUOODLE_MAX_POLICY_HASH];
  CHAR os_build_json[160];
  CHAR os_version_json[160];
  CHAR os_product_name_json[320];
  CHAR arch_json[96];
  CHAR cpu_model_json[320];
  CHAR policy_hash_json[320];
  CHAR os_ubr_json[64];
  CHAR ram_total_json[64];
  CHAR ram_available_json[64];
  CHAR payload[4096];
  size_t payload_len = 0;
  ULONG os_ubr = 0;
  ULONGLONG ram_total_mb = 0;
  ULONGLONG uptime_sec = 0;
  ULONGLONG collection_ts = q_opcode_unix_timestamp_seconds();
  ULONG cpu_cores = KeQueryActiveProcessorCountEx(ALL_PROCESSOR_GROUPS);
  BOOLEAN has_ubr = FALSE;
  BOOLEAN has_ram_total = FALSE;

  RtlZeroMemory(os_build, sizeof(os_build));
  RtlZeroMemory(os_version, sizeof(os_version));
  RtlZeroMemory(os_product_name, sizeof(os_product_name));
  RtlZeroMemory(cpu_model, sizeof(cpu_model));
  RtlZeroMemory(policy_hash_value, sizeof(policy_hash_value));

  (void)QueryRegistryStringValue(os_key, L"CurrentBuildNumber", os_build, sizeof(os_build));
  if (!QueryRegistryStringValue(os_key, L"DisplayVersion", os_version, sizeof(os_version))) {
    (void)QueryRegistryStringValue(os_key, L"ReleaseId", os_version, sizeof(os_version));
  }
  (void)QueryRegistryStringValue(os_key, L"ProductName", os_product_name, sizeof(os_product_name));
  has_ubr = QueryRegistryDwordValue(os_key, L"UBR", &os_ubr);
  has_ram_total = QueryTotalRamMb(&ram_total_mb);
  (void)QueryCpuModel(cpu_model, sizeof(cpu_model));
  (void)RtlStringCchCopyA(arch_value, sizeof(arch_value), KernelArchString());
  if (policy_hash && *policy_hash) {
    (void)RtlStringCchCopyA(policy_hash_value, sizeof(policy_hash_value), policy_hash);
  }
  uptime_sec = KeQueryInterruptTime() / 10000000ULL;

  if (!JsonStringOrNull(os_build, sizeof(os_build), os_build_json, sizeof(os_build_json)) ||
      !JsonStringOrNull(os_version, sizeof(os_version), os_version_json, sizeof(os_version_json)) ||
      !JsonStringOrNull(os_product_name, sizeof(os_product_name), os_product_name_json, sizeof(os_product_name_json)) ||
      !JsonStringOrNull(arch_value, sizeof(arch_value), arch_json, sizeof(arch_json)) ||
      !JsonStringOrNull(cpu_model, sizeof(cpu_model), cpu_model_json, sizeof(cpu_model_json)) ||
      !JsonStringOrNull(policy_hash_value, sizeof(policy_hash_value), policy_hash_json, sizeof(policy_hash_json))) {
    resp->status = 1;
    resp->error_code = QERR_COLLECT_INFO_FAILED;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "collect_info_failed");
    RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"error\",\"reason\":\"collect_info_failed\"}");
    resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
    return;
  }

  JsonUIntOrNull(has_ubr, (ULONGLONG)os_ubr, os_ubr_json, sizeof(os_ubr_json));
  JsonUIntOrNull(has_ram_total, ram_total_mb, ram_total_json, sizeof(ram_total_json));
  JsonUIntOrNull(FALSE, 0, ram_available_json, sizeof(ram_available_json));

  if (!NT_SUCCESS(RtlStringCchPrintfA(
          payload,
          sizeof(payload),
          "{\"schema_version\":\"v2\",\"kernel_mode\":true,\"collection_ts_unix\":%I64u,"
          "\"os_build\":%s,\"os_ubr\":%s,\"os_version\":%s,\"os_product_name\":%s,"
          "\"arch\":%s,\"cpu_logical_cores\":%u,\"cpu_model\":%s,"
          "\"ram_total_mb\":%s,\"ram_available_mb\":%s,\"uptime_sec\":%I64u,"
          "\"policy_hash\":%s}",
          collection_ts,
          os_build_json,
          os_ubr_json,
          os_version_json,
          os_product_name_json,
          arch_json,
          cpu_cores,
          cpu_model_json,
          ram_total_json,
          ram_available_json,
          uptime_sec,
          policy_hash_json))) {
    resp->status = 1;
    resp->error_code = QERR_COLLECT_INFO_FAILED;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "collect_info_failed");
    RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"error\",\"reason\":\"collect_info_failed\"}");
    resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
    return;
  }

  payload_len = q_opcode_strnlen_a(payload, sizeof(payload));
  if (payload_len >= sizeof(resp->result_json)) {
    resp->status = 1;
    resp->error_code = QERR_COLLECT_INFO_PAYLOAD_TOO_LARGE;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "collect_info_payload_too_large");
    RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"error\",\"reason\":\"collect_info_payload_too_large\"}");
    resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
    return;
  }

  resp->status = 0;
  resp->error_code = 0;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "");
  q_opcode_build_exec_id(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
  RtlCopyMemory(resp->result_json, payload, payload_len);
  resp->result_json[payload_len] = '\0';
  resp->result_length = (uint32_t)payload_len;
}
