#pragma once

#include <ntddk.h>

#include "../../quoodle_ioctl.h"

VOID QuoodleOpcodeHandlePing(_Out_ QUOODLE_IOCTL_RESPONSE* resp);
VOID QuoodleOpcodeHandleLockScreen(_Out_ QUOODLE_IOCTL_RESPONSE* resp);
VOID QuoodleOpcodeHandleReboot(_Out_ QUOODLE_IOCTL_RESPONSE* resp);
VOID QuoodleOpcodeHandleShutdown(_Out_ QUOODLE_IOCTL_RESPONSE* resp);
VOID QuoodleOpcodeHandleCollectSystemInfo(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleCaptureScreenshot(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleGetProcessList(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleKillProcess(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleListServices(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleListConnections(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleListMounts(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleNetworkInfo(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleGetActiveWindow(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleListFiles(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleDownloadFile(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleCreateDirectory(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleCreateFile(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleDeleteFile(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleDeleteDirectory(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req);
VOID QuoodleOpcodeHandleNotSupported(_Out_ QUOODLE_IOCTL_RESPONSE* resp);
