#pragma once

#include <ntddk.h>
#include <wdf.h>

#include "../../quoodle_ioctl.h"

NTSTATUS QuoodleEventPipelineInitialize(_In_ WDFDEVICE device);
VOID QuoodleEventPipelineShutdown(VOID);
BOOLEAN QuoodleEventPipelineTryPop(_Out_ QUOODLE_KERNEL_EVENT* out);
NTSTATUS QuoodleEventPipelinePendWaitRequest(_In_ WDFREQUEST request);
VOID QuoodleEventPipelineEmitOpcodeEvent(
    _In_ QUOODLE_OPCODE opcode,
    _In_ const QUOODLE_IOCTL_RESPONSE* resp,
    _In_ ULONGLONG duration_ms,
    _In_opt_ const CHAR* policy_ref);
VOID QuoodleEventPipelineMarkValidationReject(VOID);
VOID QuoodleEventPipelineEmitValidationReject(
    _In_ QUOODLE_OPCODE opcode,
    _In_ const QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const CHAR* reason_code,
    _In_ ULONGLONG duration_ms,
    _In_opt_ const CHAR* policy_ref);
VOID QuoodleEventPipelineEmitAppBlockEvent(
    _In_opt_ const CHAR* rule_id,
    _In_opt_ const CHAR* match_type,
    _In_opt_ const CHAR* matched_value,
    _In_opt_ const CHAR* image_path,
    _In_opt_ const CHAR* image_name,
    _In_opt_ const CHAR* reason_code,
    _In_opt_ const CHAR* policy_version,
    _In_opt_ const CHAR* policy_hash,
    _In_ ULONG session_id);
