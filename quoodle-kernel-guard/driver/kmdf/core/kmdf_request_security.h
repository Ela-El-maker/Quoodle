#pragma once

#include <ntddk.h>

#include "../../quoodle_ioctl.h"

VOID QuoodleRequestSecurityInitResponse(_Out_ QUOODLE_IOCTL_RESPONSE* resp, _In_opt_ const CHAR* request_id);
BOOLEAN QuoodleRequestSecurityValidatePayload(_In_ const QUOODLE_IOCTL_REQUEST* req);
BOOLEAN QuoodleRequestSecurityIsTimestampFresh(_In_ uint64_t ts);
BOOLEAN QuoodleRequestSecurityUpdateSequenceIfNew(_In_ uint64_t seq);
BOOLEAN QuoodleRequestSecurityHasHmacKey(VOID);
BOOLEAN QuoodleRequestSecurityVerifyRequestSignature(_In_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleRequestSecuritySignResponse(_Inout_ QUOODLE_IOCTL_RESPONSE* resp);
NTSTATUS QuoodleRequestSecurityLoadHmacKeyFromRegistry(_In_ PUNICODE_STRING RegistryPath);
VOID QuoodleRequestSecurityClearKey(VOID);