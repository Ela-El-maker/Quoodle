#pragma once

#include <ntddk.h>

#include "../../quoodle_ioctl.h"

VOID QuoodleOpcodeHandlePing(_Out_ QUOODLE_IOCTL_RESPONSE* resp);
VOID QuoodleOpcodeHandleReboot(_Out_ QUOODLE_IOCTL_RESPONSE* resp);
VOID QuoodleOpcodeHandleShutdown(_Out_ QUOODLE_IOCTL_RESPONSE* resp);
VOID QuoodleOpcodeHandleCollectSystemInfo(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleNotSupported(_Out_ QUOODLE_IOCTL_RESPONSE* resp);
