#pragma once

#include <ntddk.h>

#include "../../quoodle_ioctl.h"

NTSTATUS QuoodleAppLockdownInitialize(VOID);
VOID QuoodleAppLockdownShutdown(VOID);

NTSTATUS QuoodleAppLockdownReplacePolicy(
    _In_reads_or_z_(params_len) const CHAR* params,
    _In_ SIZE_T params_len,
    _Out_writes_(error_len) CHAR* error_out,
    _In_ SIZE_T error_len);

NTSTATUS QuoodleAppLockdownClearPolicy(
    _Out_writes_(error_len) CHAR* error_out,
    _In_ SIZE_T error_len);

NTSTATUS QuoodleAppLockdownGetStatusJson(
    _Out_writes_(json_len) CHAR* json_out,
    _In_ SIZE_T json_len,
    _Out_writes_(error_len) CHAR* error_out,
    _In_ SIZE_T error_len);
