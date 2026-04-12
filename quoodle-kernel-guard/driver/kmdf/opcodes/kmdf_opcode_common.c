#include "kmdf_opcode_common.h"
#include <ntstrsafe.h>
#include <intrin.h>

static LONG g_exec_counter = 0;

size_t q_opcode_strnlen_a(const CHAR* s, size_t max_len) {
  size_t len = 0;
  if (!s) {
    return 0;
  }
  while (len < max_len && s[len] != '\0') {
    len++;
  }
  return len;
}

uint64_t q_opcode_unix_timestamp_seconds(void) {
  LARGE_INTEGER system_time;
  KeQuerySystemTime(&system_time);
  return (uint64_t)((system_time.QuadPart - 116444736000000000ULL) / 10000000ULL);
}

VOID q_opcode_build_exec_id(_Out_writes_(buffer_len) char* buffer, _In_ size_t buffer_len) {
  LONG id = InterlockedIncrement(&g_exec_counter);
  (void)RtlStringCchPrintfA(buffer, buffer_len, "kexec-%ld", id);
}

BOOLEAN QueryRegistryStringValue(
    _In_ PCWSTR key_path,
    _In_ PCWSTR value_name,
    _Out_writes_(out_len) CHAR* out,
    _In_ size_t out_len) {
  OBJECT_ATTRIBUTES attrs;
  UNICODE_STRING key_name;
  UNICODE_STRING value_name_us;
  HANDLE key = NULL;
  NTSTATUS status;
  UCHAR buffer[512];
  ULONG result_len = 0;

  if (!out || out_len < 2) {
    return FALSE;
  }
  out[0] = '\0';

  RtlInitUnicodeString(&key_name, key_path);
  InitializeObjectAttributes(&attrs, &key_name, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
  status = ZwOpenKey(&key, KEY_READ, &attrs);
  if (!NT_SUCCESS(status)) {
    return FALSE;
  }

  RtlInitUnicodeString(&value_name_us, value_name);
  status = ZwQueryValueKey(
      key,
      &value_name_us,
      KeyValuePartialInformation,
      buffer,
      sizeof(buffer),
      &result_len);
  ZwClose(key);

  if (!NT_SUCCESS(status)) {
    return FALSE;
  }

  PKEY_VALUE_PARTIAL_INFORMATION kv = (PKEY_VALUE_PARTIAL_INFORMATION)buffer;
  if (kv->Type != REG_SZ && kv->Type != REG_EXPAND_SZ) {
    return FALSE;
  }
  if (kv->DataLength < sizeof(WCHAR)) {
    return FALSE;
  }

  UNICODE_STRING unicode_value;
  unicode_value.Buffer = (PWCHAR)kv->Data;
  unicode_value.Length = (USHORT)min((ULONG)0xFFFE, kv->DataLength);
  unicode_value.MaximumLength = unicode_value.Length;
  while (unicode_value.Length >= sizeof(WCHAR) &&
         unicode_value.Buffer[(unicode_value.Length / sizeof(WCHAR)) - 1] == L'\0') {
    unicode_value.Length -= sizeof(WCHAR);
  }

  ANSI_STRING ansi_value;
  RtlZeroMemory(&ansi_value, sizeof(ansi_value));
  status = RtlUnicodeStringToAnsiString(&ansi_value, &unicode_value, TRUE);
  if (!NT_SUCCESS(status) || ansi_value.Buffer == NULL) {
    return FALSE;
  }

  (void)RtlStringCchCopyNA(out, out_len, ansi_value.Buffer, ansi_value.Length);
  out[out_len - 1] = '\0';
  RtlFreeAnsiString(&ansi_value);
  return out[0] != '\0';
}

BOOLEAN QueryRegistryDwordValue(
    _In_ PCWSTR key_path,
    _In_ PCWSTR value_name,
    _Out_ ULONG* out_value) {
  OBJECT_ATTRIBUTES attrs;
  UNICODE_STRING key_name;
  UNICODE_STRING value_name_us;
  HANDLE key = NULL;
  NTSTATUS status;
  UCHAR buffer[128];
  ULONG result_len = 0;

  if (!out_value) {
    return FALSE;
  }
  *out_value = 0;

  RtlInitUnicodeString(&key_name, key_path);
  InitializeObjectAttributes(&attrs, &key_name, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
  status = ZwOpenKey(&key, KEY_READ, &attrs);
  if (!NT_SUCCESS(status)) {
    return FALSE;
  }

  RtlInitUnicodeString(&value_name_us, value_name);
  status = ZwQueryValueKey(
      key,
      &value_name_us,
      KeyValuePartialInformation,
      buffer,
      sizeof(buffer),
      &result_len);
  ZwClose(key);

  if (!NT_SUCCESS(status)) {
    return FALSE;
  }

  PKEY_VALUE_PARTIAL_INFORMATION kv = (PKEY_VALUE_PARTIAL_INFORMATION)buffer;
  if (kv->Type != REG_DWORD || kv->DataLength < sizeof(ULONG)) {
    return FALSE;
  }

  *out_value = *(ULONG*)kv->Data;
  return TRUE;
}

const CHAR* KernelArchString(VOID) {
#if defined(_AMD64_)
  return "x64";
#elif defined(_ARM64_)
  return "arm64";
#elif defined(_X86_)
  return "x86";
#else
  return "unknown";
#endif
}

BOOLEAN QueryCpuModel(_Out_writes_(out_len) CHAR* out, _In_ size_t out_len) {
#if !defined(_AMD64_) && !defined(_M_X64) && !defined(_X86_) && !defined(_M_IX86)
  UNREFERENCED_PARAMETER(out);
  UNREFERENCED_PARAMETER(out_len);
  return FALSE;
#else
  int cpu_info[4] = {0};
  CHAR brand[49];
  int* brand_words = (int*)brand;
  size_t len = 0;
  size_t start = 0;

  if (!out || out_len < 2) {
    return FALSE;
  }
  out[0] = '\0';

  __cpuid(cpu_info, 0x80000000);
  if ((UINT32)cpu_info[0] < 0x80000004) {
    return FALSE;
  }

  RtlZeroMemory(brand, sizeof(brand));
  __cpuid(cpu_info, 0x80000002);
  brand_words[0] = cpu_info[0];
  brand_words[1] = cpu_info[1];
  brand_words[2] = cpu_info[2];
  brand_words[3] = cpu_info[3];
  __cpuid(cpu_info, 0x80000003);
  brand_words[4] = cpu_info[0];
  brand_words[5] = cpu_info[1];
  brand_words[6] = cpu_info[2];
  brand_words[7] = cpu_info[3];
  __cpuid(cpu_info, 0x80000004);
  brand_words[8] = cpu_info[0];
  brand_words[9] = cpu_info[1];
  brand_words[10] = cpu_info[2];
  brand_words[11] = cpu_info[3];

  len = q_opcode_strnlen_a(brand, sizeof(brand));
  while (len > 0 && brand[len - 1] == ' ') {
    brand[--len] = '\0';
  }
  while (start < len && brand[start] == ' ') {
    start++;
  }
  if (start > 0 && start < len) {
    RtlMoveMemory(brand, brand + start, len - start + 1);
  }

  if (brand[0] == '\0') {
    return FALSE;
  }
  (void)RtlStringCchCopyA(out, out_len, brand);
  out[out_len - 1] = '\0';
  return TRUE;
#endif
}

BOOLEAN QueryTotalRamMb(_Out_ ULONGLONG* out_total_mb) {
  PPHYSICAL_MEMORY_RANGE ranges;
  ULONGLONG total_bytes = 0;
  ULONG idx = 0;

  if (!out_total_mb) {
    return FALSE;
  }
  *out_total_mb = 0;

  ranges = MmGetPhysicalMemoryRanges();
  if (!ranges) {
    return FALSE;
  }

  while (ranges[idx].BaseAddress.QuadPart != 0 || ranges[idx].NumberOfBytes.QuadPart != 0) {
    total_bytes += ranges[idx].NumberOfBytes.QuadPart;
    idx++;
  }

  ExFreePool(ranges);
  *out_total_mb = total_bytes / (1024ULL * 1024ULL);
  return TRUE;
}

BOOLEAN JsonEscape(
    _In_reads_or_z_(in_len) const CHAR* in,
    _In_ size_t in_len,
    _Out_writes_(out_len) CHAR* out,
    _In_ size_t out_len) {
  size_t i;
  size_t j = 0;

  if (!in || !out || out_len < 2) {
    return FALSE;
  }
  out[0] = '\0';

  for (i = 0; i < in_len && in[i] != '\0'; ++i) {
    UCHAR c = (UCHAR)in[i];
    if (j + 2 >= out_len) {
      return FALSE;
    }
    if (c == '"' || c == '\\') {
      out[j++] = '\\';
      out[j++] = (CHAR)c;
      continue;
    }
    if (c < 0x20) {
      return FALSE;
    }
    out[j++] = (CHAR)c;
  }

  out[j] = '\0';
  return TRUE;
}

BOOLEAN JsonStringOrNull(
    _In_reads_or_z_(value_len) const CHAR* value,
    _In_ size_t value_len,
    _Out_writes_(out_len) CHAR* out,
    _In_ size_t out_len) {
  CHAR escaped[512];
  NTSTATUS status;
  if (!out || out_len < 2) {
    return FALSE;
  }

  if (!value || value[0] == '\0') {
    (void)RtlStringCchCopyA(out, out_len, "null");
    out[out_len - 1] = '\0';
    return TRUE;
  }

  if (!JsonEscape(value, value_len, escaped, sizeof(escaped))) {
    return FALSE;
  }

  status = RtlStringCchPrintfA(out, out_len, "\"%s\"", escaped);
  if (!NT_SUCCESS(status)) {
    return FALSE;
  }
  return TRUE;
}

VOID JsonUIntOrNull(
    _In_ BOOLEAN has_value,
    _In_ ULONGLONG value,
    _Out_writes_(out_len) CHAR* out,
    _In_ size_t out_len) {
  if (!out || out_len < 2) {
    return;
  }
  if (!has_value) {
    (void)RtlStringCchCopyA(out, out_len, "null");
    out[out_len - 1] = '\0';
    return;
  }
  (void)RtlStringCchPrintfA(out, out_len, "%I64u", value);
  out[out_len - 1] = '\0';
}
