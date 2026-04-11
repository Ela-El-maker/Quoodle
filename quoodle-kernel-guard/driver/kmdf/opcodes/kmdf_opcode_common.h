#pragma once

#include <ntddk.h>

#include "../../quoodle_ioctl.h"

typedef enum _QUOODLE_SHUTDOWN_ACTION {
  QuoodleShutdownNoReboot = 0,
  QuoodleShutdownReboot = 1,
  QuoodleShutdownPowerOff = 2
} QUOODLE_SHUTDOWN_ACTION;

NTSYSAPI NTSTATUS NTAPI NtShutdownSystem(_In_ QUOODLE_SHUTDOWN_ACTION Action);

size_t q_opcode_strnlen_a(_In_reads_or_z_(max_len) const CHAR* s, _In_ size_t max_len);
uint64_t q_opcode_unix_timestamp_seconds(void);
VOID q_opcode_build_exec_id(_Out_writes_(buffer_len) char* buffer, _In_ size_t buffer_len);

BOOLEAN QueryRegistryStringValue(
    _In_ PCWSTR key_path,
    _In_ PCWSTR value_name,
    _Out_writes_(out_len) CHAR* out,
    _In_ size_t out_len);

BOOLEAN QueryRegistryDwordValue(
    _In_ PCWSTR key_path,
    _In_ PCWSTR value_name,
    _Out_ ULONG* out_value);

const CHAR* KernelArchString(VOID);

BOOLEAN QueryCpuModel(_Out_writes_(out_len) CHAR* out, _In_ size_t out_len);
BOOLEAN QueryTotalRamMb(_Out_ ULONGLONG* out_total_mb);

BOOLEAN JsonEscape(
    _In_reads_or_z_(in_len) const CHAR* in,
    _In_ size_t in_len,
    _Out_writes_(out_len) CHAR* out,
    _In_ size_t out_len);

BOOLEAN JsonStringOrNull(
    _In_reads_or_z_(value_len) const CHAR* value,
    _In_ size_t value_len,
    _Out_writes_(out_len) CHAR* out,
    _In_ size_t out_len);

VOID JsonUIntOrNull(
    _In_ BOOLEAN has_value,
    _In_ ULONGLONG value,
    _Out_writes_(out_len) CHAR* out,
    _In_ size_t out_len);
