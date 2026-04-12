#include "kmdf_opcode_common.h"
#include "kmdf_opcode_handlers.h"
#include <ntstrsafe.h>

typedef struct _QUOODLE_COLLECT_INFO_SELECTION {
  BOOLEAN identity;
  BOOLEAN os;
  BOOLEAN hardware;
  BOOLEAN runtime;
  BOOLEAN storage;
  BOOLEAN network;
  BOOLEAN security;
} QUOODLE_COLLECT_INFO_SELECTION;

typedef struct _QUOODLE_COLLECT_INFO_CONTEXT {
  ULONGLONG collection_ts_unix;
  CHAR policy_hash[QUOODLE_MAX_POLICY_HASH];
  BOOLEAN has_hostname;
  CHAR hostname[96];
  BOOLEAN has_computer_name;
  CHAR computer_name[96];
  BOOLEAN has_machine_guid;
  CHAR machine_guid[96];
  BOOLEAN has_smbios_uuid;
  CHAR smbios_uuid[96];
  BOOLEAN has_system_serial;
  CHAR system_serial[96];
  BOOLEAN has_baseboard_serial;
  CHAR baseboard_serial[96];
  BOOLEAN has_bios_vendor;
  CHAR bios_vendor[96];
  BOOLEAN has_os_product_name;
  CHAR os_product_name[128];
  BOOLEAN has_os_version;
  CHAR os_version[64];
  BOOLEAN has_os_build;
  CHAR os_build[64];
  BOOLEAN has_os_ubr;
  ULONG os_ubr;
  BOOLEAN has_arch;
  CHAR arch[32];
  BOOLEAN has_cpu_model;
  CHAR cpu_model[96];
  BOOLEAN has_cpu_logical_cores;
  ULONG cpu_logical_cores;
  BOOLEAN has_ram_total_mb;
  ULONGLONG ram_total_mb;
  BOOLEAN has_ram_available_mb;
  ULONGLONG ram_available_mb;
  BOOLEAN has_uptime_sec;
  ULONGLONG uptime_sec;
  BOOLEAN has_ioctl_contract_version;
  ULONG ioctl_contract_version;
  BOOLEAN has_loaded_driver_count;
  ULONG loaded_driver_count;
  BOOLEAN has_security_code_integrity;
  BOOLEAN security_code_integrity;
  BOOLEAN has_security_test_signing;
  BOOLEAN security_test_signing;
  BOOLEAN has_security_hvci_enabled;
  BOOLEAN security_hvci_enabled;
  BOOLEAN has_security_dse_enabled;
  BOOLEAN security_dse_enabled;
  BOOLEAN has_security_vbs_enabled;
  BOOLEAN security_vbs_enabled;
  BOOLEAN has_security_memory_integrity;
  BOOLEAN security_memory_integrity;
} QUOODLE_COLLECT_INFO_CONTEXT;

#ifndef Q_SYSTEM_CODEINTEGRITY_INFORMATION_CLASS
#define Q_SYSTEM_CODEINTEGRITY_INFORMATION_CLASS 103u
#endif

#ifndef Q_SYSTEM_MODULE_INFORMATION_CLASS
#define Q_SYSTEM_MODULE_INFORMATION_CLASS 11u
#endif

#define QUOODLE_COLLECT_MODULE_POOL_TAG 'mIcQ'

#ifndef NonPagedPoolNx
#define NonPagedPoolNx NonPagedPool
#endif

NTSYSAPI NTSTATUS NTAPI ZwQuerySystemInformation(
    _In_ ULONG SystemInformationClass,
    _Out_writes_bytes_to_opt_(SystemInformationLength, *ReturnLength) PVOID SystemInformation,
    _In_ ULONG SystemInformationLength,
    _Out_opt_ PULONG ReturnLength);

#ifndef CODEINTEGRITY_OPTION_ENABLED
#define CODEINTEGRITY_OPTION_ENABLED 0x01
#endif

#ifndef CODEINTEGRITY_OPTION_TESTSIGN
#define CODEINTEGRITY_OPTION_TESTSIGN 0x02
#endif

#ifndef CODEINTEGRITY_OPTION_HVCI_KMCI_ENABLED
#define CODEINTEGRITY_OPTION_HVCI_KMCI_ENABLED 0x400
#endif

#ifndef CODEINTEGRITY_OPTION_HVCI_KMCI_AUDITMODE_ENABLED
#define CODEINTEGRITY_OPTION_HVCI_KMCI_AUDITMODE_ENABLED 0x800
#endif

typedef struct _QUOODLE_SYSTEM_CODEINTEGRITY_INFORMATION {
  ULONG Length;
  ULONG CodeIntegrityOptions;
} QUOODLE_SYSTEM_CODEINTEGRITY_INFORMATION, *PQUOODLE_SYSTEM_CODEINTEGRITY_INFORMATION;

typedef struct _QUOODLE_SYSTEM_MODULE_ENTRY {
  HANDLE Section;
  PVOID MappedBase;
  PVOID ImageBase;
  ULONG ImageSize;
  ULONG Flags;
  USHORT LoadOrderIndex;
  USHORT InitOrderIndex;
  USHORT LoadCount;
  USHORT OffsetToFileName;
  UCHAR FullPathName[256];
} QUOODLE_SYSTEM_MODULE_ENTRY, *PQUOODLE_SYSTEM_MODULE_ENTRY;

typedef struct _QUOODLE_SYSTEM_MODULE_INFORMATION {
  ULONG NumberOfModules;
  QUOODLE_SYSTEM_MODULE_ENTRY Modules[1];
} QUOODLE_SYSTEM_MODULE_INFORMATION, *PQUOODLE_SYSTEM_MODULE_INFORMATION;

static VOID q_collect_loaded_driver_count(_Inout_ QUOODLE_COLLECT_INFO_CONTEXT* ctx) {
  NTSTATUS status;
  ULONG required_len = 0;
  PQUOODLE_SYSTEM_MODULE_INFORMATION module_info = NULL;

  if (!ctx) {
    return;
  }

  status = ZwQuerySystemInformation(
      Q_SYSTEM_MODULE_INFORMATION_CLASS,
      NULL,
      0,
      &required_len);
  if (status != STATUS_INFO_LENGTH_MISMATCH || required_len < sizeof(QUOODLE_SYSTEM_MODULE_INFORMATION)) {
    return;
  }

  module_info = (PQUOODLE_SYSTEM_MODULE_INFORMATION)ExAllocatePool2(
      POOL_FLAG_NON_PAGED,
      required_len,
      QUOODLE_COLLECT_MODULE_POOL_TAG);
  if (!module_info) {
    return;
  }

  status = ZwQuerySystemInformation(
      Q_SYSTEM_MODULE_INFORMATION_CLASS,
      module_info,
      required_len,
      &required_len);
  if (NT_SUCCESS(status)) {
    ctx->has_loaded_driver_count = TRUE;
    ctx->loaded_driver_count = module_info->NumberOfModules;
  }

  ExFreePoolWithTag(module_info, QUOODLE_COLLECT_MODULE_POOL_TAG);
}

static VOID q_collect_security_integrity(_Inout_ QUOODLE_COLLECT_INFO_CONTEXT* ctx) {
  QUOODLE_SYSTEM_CODEINTEGRITY_INFORMATION ci_info;
  NTSTATUS status;
  ULONG options = 0;
  BOOLEAN hvci_enabled = FALSE;

  if (!ctx) {
    return;
  }

  RtlZeroMemory(&ci_info, sizeof(ci_info));
  ci_info.Length = sizeof(ci_info);
  status = ZwQuerySystemInformation(
      Q_SYSTEM_CODEINTEGRITY_INFORMATION_CLASS,
      &ci_info,
      sizeof(ci_info),
      NULL);
  if (!NT_SUCCESS(status)) {
    return;
  }

  options = ci_info.CodeIntegrityOptions;
  hvci_enabled = ((options & CODEINTEGRITY_OPTION_HVCI_KMCI_ENABLED) != 0) ||
                 ((options & CODEINTEGRITY_OPTION_HVCI_KMCI_AUDITMODE_ENABLED) != 0);

  ctx->has_security_code_integrity = TRUE;
  ctx->security_code_integrity = ((options & CODEINTEGRITY_OPTION_ENABLED) != 0);
  ctx->has_security_dse_enabled = TRUE;
  ctx->security_dse_enabled = ctx->security_code_integrity;
  ctx->has_security_test_signing = TRUE;
  ctx->security_test_signing = ((options & CODEINTEGRITY_OPTION_TESTSIGN) != 0);
  ctx->has_security_hvci_enabled = TRUE;
  ctx->security_hvci_enabled = hvci_enabled;
  ctx->has_security_vbs_enabled = TRUE;
  ctx->security_vbs_enabled = hvci_enabled;
  ctx->has_security_memory_integrity = TRUE;
  ctx->security_memory_integrity = hvci_enabled;
}

static VOID q_selection_set_defaults(_Out_ QUOODLE_COLLECT_INFO_SELECTION* sel) {
  sel->identity = TRUE;
  sel->os = TRUE;
  sel->hardware = TRUE;
  sel->runtime = TRUE;
  sel->storage = TRUE;
  sel->network = TRUE;
  sel->security = TRUE;
}

static VOID q_selection_set_all(_Out_ QUOODLE_COLLECT_INFO_SELECTION* sel) {
  sel->identity = TRUE;
  sel->os = TRUE;
  sel->hardware = TRUE;
  sel->runtime = TRUE;
  sel->storage = TRUE;
  sel->network = TRUE;
  sel->security = TRUE;
}

static VOID q_collect_info_fail(_Out_ QUOODLE_IOCTL_RESPONSE* resp, _In_ ULONG error_code, _In_z_ const CHAR* error_message) {
  const CHAR* reason = "collect_info_failed";
  if (error_code == QERR_BAD_PAYLOAD) {
    reason = "bad_payload";
  } else if (error_code == QERR_COLLECT_INFO_PAYLOAD_TOO_LARGE) {
    reason = "collect_info_payload_too_large";
  }

  resp->status = 1;
  resp->error_code = error_code;
  (void)RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), error_message);
  (void)RtlStringCchPrintfA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"error\",\"reason\":\"%s\"}", reason);
  resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
}

static VOID q_copy_params_json(_In_opt_ const QUOODLE_IOCTL_REQUEST* req, _Out_writes_(out_len) CHAR* out, _In_ size_t out_len) {
  size_t copy_len = 0;

  if (!out || out_len < 2) {
    return;
  }
  out[0] = '\0';
  if (!req) {
    return;
  }

  copy_len = (size_t)req->params_length;
  if (copy_len >= out_len) {
    copy_len = out_len - 1;
  }
  if (copy_len > QUOODLE_MAX_PARAMS - 1) {
    copy_len = QUOODLE_MAX_PARAMS - 1;
  }
  if (copy_len > 0) {
    RtlCopyMemory(out, req->params_json, copy_len);
    out[copy_len] = '\0';
  }
}

static BOOLEAN q_is_space(_In_ CHAR c) {
  return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

static const CHAR* q_find_substring(
    _In_reads_(hay_len) const CHAR* haystack,
    _In_ size_t hay_len,
    _In_reads_(needle_len) const CHAR* needle,
    _In_ size_t needle_len) {
  size_t i = 0;
  size_t j = 0;

  if (!haystack || !needle || needle_len == 0 || hay_len < needle_len) {
    return NULL;
  }

  for (i = 0; i + needle_len <= hay_len; ++i) {
    BOOLEAN match = TRUE;
    for (j = 0; j < needle_len; ++j) {
      if (haystack[i + j] != needle[j]) {
        match = FALSE;
        break;
      }
    }
    if (match) {
      return haystack + i;
    }
  }
  return NULL;
}

static VOID q_skip_ws(_In_reads_(len) const CHAR* json, _In_ size_t len, _Inout_ size_t* idx) {
  while (*idx < len && q_is_space(json[*idx])) {
    (*idx)++;
  }
}

static BOOLEAN q_parse_json_string_token(
    _In_reads_(json_len) const CHAR* json,
    _In_ size_t json_len,
    _Inout_ size_t* idx,
    _Out_writes_(token_len) CHAR* token_out,
    _In_ size_t token_len) {
  size_t out_idx = 0;

  if (*idx >= json_len || json[*idx] != '"' || !token_out || token_len < 2) {
    return FALSE;
  }
  (*idx)++;

  while (*idx < json_len) {
    CHAR ch = json[*idx];
    if (ch == '"') {
      token_out[out_idx] = '\0';
      (*idx)++;
      return TRUE;
    }
    if (ch == '\\') {
      (*idx)++;
      if (*idx >= json_len) {
        return FALSE;
      }
      ch = json[*idx];
    }
    if (out_idx + 1 >= token_len) {
      return FALSE;
    }
    token_out[out_idx++] = ch;
    (*idx)++;
  }

  return FALSE;
}

static BOOLEAN q_apply_selector(_In_z_ const CHAR* selector, _Inout_ QUOODLE_COLLECT_INFO_SELECTION* sel) {
  if (RtlCompareMemory(selector, "identity", 8) == 8 && selector[8] == '\0') {
    sel->identity = TRUE;
    return TRUE;
  }
  if (RtlCompareMemory(selector, "os", 2) == 2 && selector[2] == '\0') {
    sel->os = TRUE;
    return TRUE;
  }
  if (RtlCompareMemory(selector, "hardware", 8) == 8 && selector[8] == '\0') {
    sel->hardware = TRUE;
    return TRUE;
  }
  if (RtlCompareMemory(selector, "runtime", 7) == 7 && selector[7] == '\0') {
    sel->runtime = TRUE;
    return TRUE;
  }
  if (RtlCompareMemory(selector, "storage", 7) == 7 && selector[7] == '\0') {
    sel->storage = TRUE;
    return TRUE;
  }
  if (RtlCompareMemory(selector, "network", 7) == 7 && selector[7] == '\0') {
    sel->network = TRUE;
    return TRUE;
  }
  if (RtlCompareMemory(selector, "security", 8) == 8 && selector[8] == '\0') {
    sel->security = TRUE;
    return TRUE;
  }
  if (RtlCompareMemory(selector, "all", 3) == 3 && selector[3] == '\0') {
    q_selection_set_all(sel);
    return TRUE;
  }
  return FALSE;
}

static BOOLEAN q_collect_info_parse_selection(
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req,
    _Out_ QUOODLE_COLLECT_INFO_SELECTION* sel) {
  CHAR params_json[QUOODLE_MAX_PARAMS];
  const CHAR fields_token[] = "\"fields\"";
  const CHAR* fields_pos = NULL;
  size_t json_len = 0;
  size_t idx = 0;
  BOOLEAN closed = FALSE;

  if (!sel) {
    return FALSE;
  }
  RtlZeroMemory(sel, sizeof(*sel));
  q_selection_set_defaults(sel);

  q_copy_params_json(req, params_json, sizeof(params_json));
  if (params_json[0] == '\0') {
    return TRUE;
  }

  fields_pos = q_find_substring(params_json, q_opcode_strnlen_a(params_json, sizeof(params_json)), fields_token, sizeof(fields_token) - 1);
  if (!fields_pos) {
    return TRUE;
  }

  RtlZeroMemory(sel, sizeof(*sel));
  json_len = q_opcode_strnlen_a(params_json, sizeof(params_json));
  idx = (size_t)(fields_pos - params_json) + (sizeof(fields_token) - 1);
  q_skip_ws(params_json, json_len, &idx);
  if (idx >= json_len || params_json[idx] != ':') {
    return FALSE;
  }
  idx++;
  q_skip_ws(params_json, json_len, &idx);
  if (idx >= json_len || params_json[idx] != '[') {
    return FALSE;
  }
  idx++;

  while (idx < json_len) {
    CHAR selector[32];
    q_skip_ws(params_json, json_len, &idx);
    if (idx >= json_len) {
      break;
    }
    if (params_json[idx] == ']') {
      closed = TRUE;
      idx++;
      break;
    }
    if (!q_parse_json_string_token(params_json, json_len, &idx, selector, sizeof(selector))) {
      return FALSE;
    }
    if (!q_apply_selector(selector, sel)) {
      return FALSE;
    }
    q_skip_ws(params_json, json_len, &idx);
    if (idx >= json_len) {
      return FALSE;
    }
    if (params_json[idx] == ',') {
      idx++;
      continue;
    }
    if (params_json[idx] == ']') {
      closed = TRUE;
      idx++;
      break;
    }
    return FALSE;
  }

  return closed;
}

static VOID q_collect_info_init_context(
    _Out_ QUOODLE_COLLECT_INFO_CONTEXT* ctx,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  const WCHAR* os_key = L"\\Registry\\Machine\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";
  const WCHAR* hostname_key = L"\\Registry\\Machine\\SYSTEM\\CurrentControlSet\\Control\\ComputerName\\ComputerName";
  const WCHAR* machine_guid_key = L"\\Registry\\Machine\\SOFTWARE\\Microsoft\\Cryptography";
  const WCHAR* firmware_key = L"\\Registry\\Machine\\HARDWARE\\DESCRIPTION\\System\\BIOS";

  if (!ctx) {
    return;
  }

  RtlZeroMemory(ctx, sizeof(*ctx));
  ctx->collection_ts_unix = q_opcode_unix_timestamp_seconds();

  ctx->has_hostname = QueryRegistryStringValue(hostname_key, L"ComputerName", ctx->hostname, sizeof(ctx->hostname));
  ctx->has_computer_name = QueryRegistryStringValue(hostname_key, L"ComputerName", ctx->computer_name, sizeof(ctx->computer_name));
  ctx->has_machine_guid = QueryRegistryStringValue(machine_guid_key, L"MachineGuid", ctx->machine_guid, sizeof(ctx->machine_guid));
  ctx->has_smbios_uuid = QueryRegistryStringValue(firmware_key, L"SystemUUID", ctx->smbios_uuid, sizeof(ctx->smbios_uuid));
  ctx->has_system_serial = QueryRegistryStringValue(firmware_key, L"SystemSerialNumber", ctx->system_serial, sizeof(ctx->system_serial));
  ctx->has_baseboard_serial = QueryRegistryStringValue(firmware_key, L"BaseBoardSerialNumber", ctx->baseboard_serial, sizeof(ctx->baseboard_serial));
  ctx->has_bios_vendor = QueryRegistryStringValue(firmware_key, L"BIOSVendor", ctx->bios_vendor, sizeof(ctx->bios_vendor));
  ctx->has_os_build = QueryRegistryStringValue(os_key, L"CurrentBuildNumber", ctx->os_build, sizeof(ctx->os_build));
  ctx->has_os_version = QueryRegistryStringValue(os_key, L"DisplayVersion", ctx->os_version, sizeof(ctx->os_version));
  if (!ctx->has_os_version) {
    ctx->has_os_version = QueryRegistryStringValue(os_key, L"ReleaseId", ctx->os_version, sizeof(ctx->os_version));
  }
  ctx->has_os_product_name = QueryRegistryStringValue(os_key, L"ProductName", ctx->os_product_name, sizeof(ctx->os_product_name));
  ctx->has_os_ubr = QueryRegistryDwordValue(os_key, L"UBR", &ctx->os_ubr);

  if (NT_SUCCESS(RtlStringCchCopyA(ctx->arch, sizeof(ctx->arch), KernelArchString()))) {
    ctx->has_arch = ctx->arch[0] != '\0';
  }
  ctx->has_cpu_model = QueryCpuModel(ctx->cpu_model, sizeof(ctx->cpu_model));
  ctx->cpu_logical_cores = KeQueryActiveProcessorCountEx(ALL_PROCESSOR_GROUPS);
  ctx->has_cpu_logical_cores = TRUE;
  ctx->has_ram_total_mb = QueryTotalRamMb(&ctx->ram_total_mb);
  ctx->has_ram_available_mb = FALSE;
  ctx->ram_available_mb = 0;

  ctx->uptime_sec = KeQueryInterruptTime() / 10000000ULL;
  ctx->has_uptime_sec = TRUE;
  ctx->ioctl_contract_version = QUOODLE_IOCTL_VERSION;
  ctx->has_ioctl_contract_version = TRUE;

  if (req && req->policy_hash[0] != '\0') {
    (void)RtlStringCchCopyA(ctx->policy_hash, sizeof(ctx->policy_hash), req->policy_hash);
  } else {
    ctx->policy_hash[0] = '\0';
  }

  q_collect_loaded_driver_count(ctx);
  q_collect_security_integrity(ctx);
}

static VOID q_copy_string_bounded(_Out_writes_(dest_len) CHAR* dest, _In_ size_t dest_len, _In_z_ const CHAR* src) {
  if (!dest || dest_len < 1) {
    return;
  }
  if (!src) {
    dest[0] = '\0';
    return;
  }
  (void)RtlStringCchCopyA(dest, dest_len, src);
  dest[dest_len - 1] = '\0';
}

static uint32_t q_collect_sections_mask(_In_ const QUOODLE_COLLECT_INFO_SELECTION* sel) {
  uint32_t mask = 0;
  if (sel->identity) mask |= QUOODLE_COLLECT_SECTION_IDENTITY;
  if (sel->os) mask |= QUOODLE_COLLECT_SECTION_OS;
  if (sel->hardware) mask |= QUOODLE_COLLECT_SECTION_HARDWARE;
  if (sel->runtime) mask |= QUOODLE_COLLECT_SECTION_RUNTIME;
  if (sel->storage) mask |= QUOODLE_COLLECT_SECTION_STORAGE;
  if (sel->network) mask |= QUOODLE_COLLECT_SECTION_NETWORK;
  if (sel->security) mask |= QUOODLE_COLLECT_SECTION_SECURITY;
  return mask;
}

static VOID q_collect_fill_binary_header(
    _In_ const QUOODLE_COLLECT_INFO_CONTEXT* ctx,
    _In_ const QUOODLE_COLLECT_INFO_SELECTION* sel,
    _Out_ QUOODLE_COLLECT_INFO_BINARY_V1* payload) {
  RtlZeroMemory(payload, sizeof(*payload));
  payload->magic = QUOODLE_COLLECT_INFO_BINARY_MAGIC;
  payload->version = QUOODLE_COLLECT_INFO_BINARY_VERSION;
  payload->reserved = 0;
  payload->sections_mask = q_collect_sections_mask(sel);
  payload->fields_present_mask = 0;
  payload->flags = 0;
  payload->collection_ts_unix = ctx->collection_ts_unix;
}

static VOID FillIdentitySectionBinary(
    _In_ const QUOODLE_COLLECT_INFO_CONTEXT* ctx,
    _In_ BOOLEAN include_section,
    _Inout_ QUOODLE_COLLECT_INFO_BINARY_V1* payload) {
  if (include_section && ctx->has_hostname) {
    q_copy_string_bounded(payload->hostname, sizeof(payload->hostname), ctx->hostname);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_HOSTNAME;
  }
  if (include_section && ctx->has_computer_name) {
    q_copy_string_bounded(payload->computer_name, sizeof(payload->computer_name), ctx->computer_name);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_COMPUTER_NAME;
  }
  if (include_section && ctx->has_machine_guid) {
    q_copy_string_bounded(payload->machine_guid, sizeof(payload->machine_guid), ctx->machine_guid);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_MACHINE_GUID;
  }
  if (include_section && ctx->has_smbios_uuid) {
    q_copy_string_bounded(payload->smbios_uuid, sizeof(payload->smbios_uuid), ctx->smbios_uuid);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_FIRMWARE_SMBIOS_UUID;
  }
  if (include_section && ctx->has_system_serial) {
    q_copy_string_bounded(payload->system_serial, sizeof(payload->system_serial), ctx->system_serial);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_FIRMWARE_SYSTEM_SERIAL;
  }
  if (include_section && ctx->has_baseboard_serial) {
    q_copy_string_bounded(payload->baseboard_serial, sizeof(payload->baseboard_serial), ctx->baseboard_serial);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_FIRMWARE_BASEBOARD_SERIAL;
  }
  if (include_section && ctx->has_bios_vendor) {
    q_copy_string_bounded(payload->bios_vendor, sizeof(payload->bios_vendor), ctx->bios_vendor);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_FIRMWARE_BIOS_VENDOR;
  }
}

static VOID FillOsSectionBinary(
    _In_ const QUOODLE_COLLECT_INFO_CONTEXT* ctx,
    _In_ BOOLEAN include_section,
    _Inout_ QUOODLE_COLLECT_INFO_BINARY_V1* payload) {
  if (include_section && ctx->has_os_product_name) {
    q_copy_string_bounded(payload->os_product_name, sizeof(payload->os_product_name), ctx->os_product_name);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_OS_PRODUCT_NAME;
  }
  if (include_section && ctx->has_os_version) {
    q_copy_string_bounded(payload->os_version, sizeof(payload->os_version), ctx->os_version);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_OS_VERSION;
  }
  if (include_section && ctx->has_os_build) {
    q_copy_string_bounded(payload->os_build, sizeof(payload->os_build), ctx->os_build);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_OS_BUILD;
  }
  if (include_section && ctx->has_os_ubr) {
    payload->os_ubr = ctx->os_ubr;
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_OS_UBR;
  }
  if (include_section && ctx->has_arch) {
    q_copy_string_bounded(payload->arch, sizeof(payload->arch), ctx->arch);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_ARCH;
  }
}

static VOID FillHardwareSectionBinary(
    _In_ const QUOODLE_COLLECT_INFO_CONTEXT* ctx,
    _In_ BOOLEAN include_section,
    _Inout_ QUOODLE_COLLECT_INFO_BINARY_V1* payload) {
  if (include_section && ctx->has_cpu_model) {
    q_copy_string_bounded(payload->cpu_model, sizeof(payload->cpu_model), ctx->cpu_model);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_CPU_MODEL;
  }
  if (include_section && ctx->has_cpu_logical_cores) {
    payload->cpu_logical_cores = ctx->cpu_logical_cores;
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_CPU_LOGICAL_CORES;
  }
  if (include_section && ctx->has_ram_total_mb) {
    payload->ram_total_mb = ctx->ram_total_mb;
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_RAM_TOTAL_MB;
  }
  if (include_section && ctx->has_ram_available_mb) {
    payload->ram_available_mb = ctx->ram_available_mb;
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_RAM_AVAILABLE_MB;
  } else if (include_section) {
    payload->flags |= QUOODLE_COLLECT_FLAG_RAM_AVAILABLE_NOT_COLLECTABLE;
  }
}

static VOID FillRuntimeSectionBinary(
    _In_ const QUOODLE_COLLECT_INFO_CONTEXT* ctx,
    _In_ BOOLEAN include_section,
    _Inout_ QUOODLE_COLLECT_INFO_BINARY_V1* payload) {
  if (include_section && ctx->policy_hash[0] != '\0') {
    q_copy_string_bounded(payload->policy_hash, sizeof(payload->policy_hash), ctx->policy_hash);
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_POLICY_HASH;
  }
  if (include_section && ctx->has_uptime_sec) {
    payload->uptime_sec = ctx->uptime_sec;
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_UPTIME_SEC;
  }
  if (include_section && ctx->has_ioctl_contract_version) {
    payload->ioctl_contract_version = ctx->ioctl_contract_version;
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_IOCTL_CONTRACT_VERSION;
  }
}

static VOID FillStorageSectionBinary(
    _In_ const QUOODLE_COLLECT_INFO_CONTEXT* ctx,
    _In_ BOOLEAN include_section,
    _Inout_ QUOODLE_COLLECT_INFO_BINARY_V1* payload) {
  UNREFERENCED_PARAMETER(ctx);
  if (include_section) {
    payload->flags |= QUOODLE_COLLECT_FLAG_STORAGE_NOT_IMPLEMENTED;
  }
}

static VOID FillNetworkSectionBinary(
    _In_ const QUOODLE_COLLECT_INFO_CONTEXT* ctx,
    _In_ BOOLEAN include_section,
    _Inout_ QUOODLE_COLLECT_INFO_BINARY_V1* payload) {
  UNREFERENCED_PARAMETER(ctx);
  if (include_section) {
    payload->flags |= QUOODLE_COLLECT_FLAG_NETWORK_NOT_IMPLEMENTED;
  }
}

static VOID FillSecuritySectionBinary(
    _In_ const QUOODLE_COLLECT_INFO_CONTEXT* ctx,
    _In_ BOOLEAN include_section,
    _Inout_ QUOODLE_COLLECT_INFO_BINARY_V1* payload) {
  BOOLEAN has_security_data = FALSE;

  if (!include_section) {
    return;
  }

  if (ctx->has_security_code_integrity) {
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_SECURITY_CODE_INTEGRITY;
    if (ctx->security_code_integrity) {
      payload->flags |= QUOODLE_COLLECT_FLAG_SECURITY_CODE_INTEGRITY_TRUE;
    }
    has_security_data = TRUE;
  }
  if (ctx->has_security_test_signing) {
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_SECURITY_TEST_SIGNING;
    if (ctx->security_test_signing) {
      payload->flags |= QUOODLE_COLLECT_FLAG_SECURITY_TEST_SIGNING_TRUE;
    }
    has_security_data = TRUE;
  }
  if (ctx->has_security_hvci_enabled) {
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_SECURITY_HVCI_ENABLED;
    if (ctx->security_hvci_enabled) {
      payload->flags |= QUOODLE_COLLECT_FLAG_SECURITY_HVCI_ENABLED_TRUE;
    }
    has_security_data = TRUE;
  }
  if (ctx->has_security_dse_enabled) {
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_SECURITY_DSE_ENABLED;
    if (ctx->security_dse_enabled) {
      payload->flags |= QUOODLE_COLLECT_FLAG_SECURITY_DSE_ENABLED_TRUE;
    }
    has_security_data = TRUE;
  }
  if (ctx->has_security_vbs_enabled) {
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_SECURITY_VBS_ENABLED;
    if (ctx->security_vbs_enabled) {
      payload->flags |= QUOODLE_COLLECT_FLAG_SECURITY_VBS_ENABLED_TRUE;
    }
    has_security_data = TRUE;
  }
  if (ctx->has_security_memory_integrity) {
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_SECURITY_MEMORY_INTEGRITY;
    if (ctx->security_memory_integrity) {
      payload->flags |= QUOODLE_COLLECT_FLAG_SECURITY_MEMORY_INTEGRITY_TRUE;
    }
    has_security_data = TRUE;
  }
  if (ctx->has_loaded_driver_count) {
    payload->loaded_driver_count = ctx->loaded_driver_count;
    payload->fields_present_mask |= QUOODLE_COLLECT_PRESENT_SECURITY_LOADED_DRIVER_COUNT;
    has_security_data = TRUE;
  }

  if (!has_security_data) {
    payload->flags |= QUOODLE_COLLECT_FLAG_SECURITY_NOT_IMPLEMENTED;
  }
}

static VOID q_collect_fill_binary_payload(
    _In_ const QUOODLE_COLLECT_INFO_CONTEXT* ctx,
    _In_ const QUOODLE_COLLECT_INFO_SELECTION* sel,
    _Out_ QUOODLE_COLLECT_INFO_BINARY_V1* payload) {
  q_collect_fill_binary_header(ctx, sel, payload);
  FillIdentitySectionBinary(ctx, sel->identity, payload);
  FillOsSectionBinary(ctx, sel->os, payload);
  FillHardwareSectionBinary(ctx, sel->hardware, payload);
  FillRuntimeSectionBinary(ctx, sel->runtime, payload);
  FillStorageSectionBinary(ctx, sel->storage, payload);
  FillNetworkSectionBinary(ctx, sel->network, payload);
  FillSecuritySectionBinary(ctx, sel->security, payload);
}

VOID QuoodleOpcodeHandleCollectSystemInfo(_Out_ QUOODLE_IOCTL_RESPONSE* resp, _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  QUOODLE_COLLECT_INFO_SELECTION sel;
  QUOODLE_COLLECT_INFO_CONTEXT ctx;
  QUOODLE_COLLECT_INFO_BINARY_V1 payload;

  RtlZeroMemory(&sel, sizeof(sel));
  RtlZeroMemory(&ctx, sizeof(ctx));
  RtlZeroMemory(&payload, sizeof(payload));

  if (!q_collect_info_parse_selection(req, &sel)) {
    q_collect_info_fail(resp, QERR_BAD_PAYLOAD, "bad_payload");
    return;
  }

  if (sizeof(payload) > sizeof(resp->result_json)) {
    q_collect_info_fail(resp, QERR_COLLECT_INFO_PAYLOAD_TOO_LARGE, "collect_info_payload_too_large");
    return;
  }

  q_collect_info_init_context(&ctx, req);
  q_collect_fill_binary_payload(&ctx, &sel, &payload);

  RtlZeroMemory(resp->result_json, sizeof(resp->result_json));
  RtlCopyMemory(resp->result_json, &payload, sizeof(payload));
  resp->result_length = (uint32_t)sizeof(payload);
  resp->status = 0;
  resp->error_code = 0;
  (void)RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "");
  q_opcode_build_exec_id(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
}
