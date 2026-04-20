#include <ntddk.h>
#include <wdf.h>
#include <ntstrsafe.h>

#include "../quoodle_ioctl.h"
#include "core/kmdf_app_lockdown.h"
#include "core/kmdf_event_pipeline.h"
#include "core/kmdf_request_security.h"
#include "opcodes/kmdf_opcode_handlers.h"

static VOID DeleteUserSymbolicLinks(VOID) {
  UNICODE_STRING primary_sym_link;
  UNICODE_STRING legacy_sym_link;
  RtlInitUnicodeString(&primary_sym_link, QUOODLE_DOS_DEVICE_NAME);
  RtlInitUnicodeString(&legacy_sym_link, QUOODLE_DOS_DEVICE_NAME_LEGACY);
  (VOID)IoDeleteSymbolicLink(&primary_sym_link);
  (VOID)IoDeleteSymbolicLink(&legacy_sym_link);
}

static NTSTATUS CreateUserSymbolicLinks(VOID) {
  UNICODE_STRING device_name;
  UNICODE_STRING primary_sym_link;
  UNICODE_STRING legacy_sym_link;
  NTSTATUS status;

  RtlInitUnicodeString(&device_name, QUOODLE_DEVICE_NAME);
  RtlInitUnicodeString(&primary_sym_link, QUOODLE_DOS_DEVICE_NAME);
  RtlInitUnicodeString(&legacy_sym_link, QUOODLE_DOS_DEVICE_NAME_LEGACY);

  DeleteUserSymbolicLinks();

  status = IoCreateSymbolicLink(&primary_sym_link, &device_name);
  if (!NT_SUCCESS(status) && status != STATUS_OBJECT_NAME_COLLISION) {
    return status;
  }

  status = IoCreateSymbolicLink(&legacy_sym_link, &device_name);
  if (!NT_SUCCESS(status) && status != STATUS_OBJECT_NAME_COLLISION) {
    (VOID)IoDeleteSymbolicLink(&primary_sym_link);
    return status;
  }

  return STATUS_SUCCESS;
}

static VOID QuoodleEvtIoDeviceControl(_In_ WDFQUEUE Queue,
                                      _In_ WDFREQUEST Request,
                                      _In_ size_t OutputBufferLength,
                                      _In_ size_t InputBufferLength,
                                      _In_ ULONG IoControlCode) {
  UNREFERENCED_PARAMETER(Queue);

  if (IoControlCode == IOCTL_QUOODLE_WAIT_EVENT) {
    if (OutputBufferLength < sizeof(QUOODLE_KERNEL_EVENT)) {
      WdfRequestComplete(Request, STATUS_BUFFER_TOO_SMALL);
      return;
    }

    QUOODLE_KERNEL_EVENT* out = NULL;
    SIZE_T out_len = 0;
    NTSTATUS status = WdfRequestRetrieveOutputBuffer(Request, sizeof(QUOODLE_KERNEL_EVENT), (PVOID*)&out, &out_len);
    if (!NT_SUCCESS(status) || out == NULL) {
      WdfRequestComplete(Request, STATUS_INVALID_PARAMETER);
      return;
    }

    QUOODLE_KERNEL_EVENT evt;
    if (QuoodleEventPipelineTryPop(&evt)) {
      RtlCopyMemory(out, &evt, sizeof(evt));
      WdfRequestCompleteWithInformation(Request, STATUS_SUCCESS, sizeof(QUOODLE_KERNEL_EVENT));
      return;
    }

    status = QuoodleEventPipelinePendWaitRequest(Request);
    if (!NT_SUCCESS(status)) {
      WdfRequestComplete(Request, status);
    }
    return;
  }

  if (IoControlCode != IOCTL_QUOODLE_EXECUTE) {
    WdfRequestComplete(Request, STATUS_INVALID_DEVICE_REQUEST);
    return;
  }

  if (InputBufferLength < sizeof(QUOODLE_IOCTL_REQUEST) || OutputBufferLength < sizeof(QUOODLE_IOCTL_RESPONSE)) {
    WdfRequestComplete(Request, STATUS_BUFFER_TOO_SMALL);
    return;
  }

  QUOODLE_IOCTL_REQUEST* req = NULL;
  SIZE_T req_len = 0;
  NTSTATUS status = WdfRequestRetrieveInputBuffer(Request, sizeof(QUOODLE_IOCTL_REQUEST), (PVOID*)&req, &req_len);
  if (!NT_SUCCESS(status) || req == NULL) {
    WdfRequestComplete(Request, STATUS_INVALID_PARAMETER);
    return;
  }

  // METHOD_BUFFERED can alias input/output; copy request before writing response.
  QUOODLE_IOCTL_REQUEST req_copy;
  RtlZeroMemory(&req_copy, sizeof(req_copy));
  RtlCopyMemory(&req_copy, req, sizeof(req_copy));

  QUOODLE_IOCTL_RESPONSE* resp = NULL;
  SIZE_T resp_len = 0;
  status = WdfRequestRetrieveOutputBuffer(Request, sizeof(QUOODLE_IOCTL_RESPONSE), (PVOID*)&resp, &resp_len);
  if (!NT_SUCCESS(status) || resp == NULL) {
    WdfRequestComplete(Request, STATUS_INVALID_PARAMETER);
    return;
  }

  QuoodleRequestSecurityInitResponse(resp, req_copy.request_id);

  BOOLEAN should_emit_event = FALSE;
  const CHAR* runtime_reason_code = NULL;
  QUOODLE_OPCODE opcode = (QUOODLE_OPCODE)req_copy.opcode;
  LARGE_INTEGER perf_freq = {0};
  LARGE_INTEGER perf_start = KeQueryPerformanceCounter(&perf_freq);

  if (req_copy.version != QUOODLE_IOCTL_VERSION) {
    resp->error_code = QERR_INVALID_VERSION;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "invalid_version");
    runtime_reason_code = "invalid_version";
  } else if (!QuoodleRequestSecurityValidatePayload(&req_copy)) {
    resp->error_code = QERR_BAD_PAYLOAD;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "bad_payload");
    runtime_reason_code = "bad_payload";
  } else if (!QuoodleRequestSecurityIsTimestampFresh(req_copy.timestamp_unix)) {
    resp->error_code = QERR_TIMESTAMP_SKEW;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "timestamp_skew");
    runtime_reason_code = "timestamp_skew";
  } else if (!QuoodleRequestSecurityUpdateSequenceIfNew(req_copy.agent_sequence)) {
    resp->error_code = QERR_SEQ_REPLAY;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "seq_replay");
    runtime_reason_code = "seq_replay";
  } else if (!QuoodleRequestSecurityHasHmacKey()) {
    resp->error_code = QERR_SIGNATURE_INVALID;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "signature_invalid");
    runtime_reason_code = "signature_invalid";
  } else if (req_copy.signature_length == 0) {
    resp->error_code = QERR_SIGNATURE_MISSING;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "signature_missing");
    runtime_reason_code = "signature_missing";
  } else if (req_copy.signature_length >= QUOODLE_MAX_SIG_B64 || req_copy.signature_b64[req_copy.signature_length] != '\0') {
    resp->error_code = QERR_BAD_PAYLOAD;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "bad_payload");
    runtime_reason_code = "bad_payload";
  } else if (!QuoodleRequestSecurityVerifyRequestSignature(&req_copy)) {
    resp->error_code = QERR_SIGNATURE_INVALID;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "signature_invalid");
    runtime_reason_code = "signature_invalid";
  } else {
    switch (opcode) {
      case QOP_EXEC_PING:
        QuoodleOpcodeHandlePing(resp);
        should_emit_event = TRUE;
        break;
      case QOP_EXEC_REBOOT:
        QuoodleOpcodeHandleReboot(resp);
        should_emit_event = TRUE;
        break;
      case QOP_EXEC_SHUTDOWN:
        QuoodleOpcodeHandleShutdown(resp);
        should_emit_event = TRUE;
        break;
      case QOP_EXEC_LOCK_SCREEN:
        QuoodleOpcodeHandleLockScreen(resp);
        should_emit_event = TRUE;
        break;
      case QOP_EXEC_LOGOUT:
      case QOP_EXEC_VALIDATE_UPDATE_PACKAGE:
      case QOP_STAGE_UPDATE:
      case QOP_COMMIT_UPDATE:
      case QOP_ROLLBACK_UPDATE:
      case QOP_EXEC_RUN_ATTESTATION:
      case QOP_EXEC_RUN_TAMPER_CHECK:
      case QOP_EXEC_SELF_REPAIR:
        QuoodleOpcodeHandleNotSupported(resp);
        should_emit_event = TRUE;
        break;
      case QOP_EXEC_GET_PROCESS_LIST:
      case QOP_OBS_LIST_PROCESSES:
        QuoodleOpcodeHandleGetProcessList(resp, &req_copy);
        should_emit_event = TRUE;
        break;
      case QOP_EXEC_KILL_PROCESS:
        QuoodleOpcodeHandleKillProcess(resp, &req_copy);
        should_emit_event = TRUE;
        break;
      case QOP_OBS_LIST_SERVICES:
        QuoodleOpcodeHandleListServices(resp, &req_copy);
        should_emit_event = TRUE;
        break;
      case QOP_OBS_LIST_CONNECTIONS:
        QuoodleOpcodeHandleListConnections(resp, &req_copy);
        should_emit_event = TRUE;
        break;
      case QOP_OBS_LIST_MOUNTS:
        QuoodleOpcodeHandleListMounts(resp, &req_copy);
        should_emit_event = TRUE;
        break;
      case QOP_OBS_NETWORK_INFO:
        QuoodleOpcodeHandleNetworkInfo(resp, &req_copy);
        should_emit_event = TRUE;
        break;
      case QOP_OBS_GET_ACTIVE_WINDOW:
        QuoodleOpcodeHandleGetActiveWindow(resp, &req_copy);
        should_emit_event = TRUE;
        break;
      case QOP_FS_LIST_FILES:
        QuoodleOpcodeHandleListFiles(resp, &req_copy);
        should_emit_event = TRUE;
        break;
      case QOP_FS_DOWNLOAD_FILE:
        QuoodleOpcodeHandleDownloadFile(resp, &req_copy);
        should_emit_event = TRUE;
        break;
      case QOP_SEC_APPLOCK_REPLACE_POLICY: {
        CHAR error_reason[sizeof(resp->error_message)];
        NTSTATUS app_status = QuoodleAppLockdownReplacePolicy(
            req_copy.params_json,
            (SIZE_T)req_copy.params_length,
            error_reason,
            sizeof(error_reason));
        if (!NT_SUCCESS(app_status)) {
          resp->error_code = QERR_BAD_PAYLOAD;
          RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), error_reason[0] != '\0' ? error_reason : "app_lock_replace_failed");
        } else {
          const CHAR* ok_json = "{\"status\":\"ok\"}";
          size_t json_len = 0;
          resp->status = 0;
          if (NT_SUCCESS(RtlStringCchLengthA(ok_json, sizeof(resp->result_json), &json_len))) {
            resp->result_length = (uint32_t)json_len;
          }
          RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), ok_json);
        }
        should_emit_event = TRUE;
        break;
      }
      case QOP_SEC_APPLOCK_GET_STATUS: {
        CHAR error_reason[sizeof(resp->error_message)];
        CHAR status_json[QUOODLE_MAX_RESULT];
        RtlZeroMemory(status_json, sizeof(status_json));
        NTSTATUS app_status = QuoodleAppLockdownGetStatusJson(
            status_json,
            sizeof(status_json),
            error_reason,
            sizeof(error_reason));
        if (!NT_SUCCESS(app_status)) {
          resp->error_code = QERR_BAD_PAYLOAD;
          RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), error_reason[0] != '\0' ? error_reason : "app_lock_status_failed");
        } else {
          size_t json_len = 0;
          resp->status = 0;
          if (NT_SUCCESS(RtlStringCchLengthA(status_json, sizeof(resp->result_json), &json_len))) {
            resp->result_length = (uint32_t)json_len;
          }
          RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), status_json);
        }
        should_emit_event = TRUE;
        break;
      }
      case QOP_SEC_APPLOCK_CLEAR_POLICY: {
        CHAR error_reason[sizeof(resp->error_message)];
        NTSTATUS app_status = QuoodleAppLockdownClearPolicy(
            error_reason,
            sizeof(error_reason));
        if (!NT_SUCCESS(app_status)) {
          resp->error_code = QERR_BAD_PAYLOAD;
          RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), error_reason[0] != '\0' ? error_reason : "app_lock_clear_failed");
        } else {
          const CHAR* ok_json = "{\"status\":\"ok\"}";
          size_t json_len = 0;
          resp->status = 0;
          if (NT_SUCCESS(RtlStringCchLengthA(ok_json, sizeof(resp->result_json), &json_len))) {
            resp->result_length = (uint32_t)json_len;
          }
          RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), ok_json);
        }
        should_emit_event = TRUE;
        break;
      }
      case QOP_EXEC_COLLECT_SYSTEM_INFO:
        QuoodleOpcodeHandleCollectSystemInfo(resp, &req_copy);
        should_emit_event = TRUE;
        break;
      case QOP_EXEC_CAPTURE_SCREENSHOT:
        QuoodleOpcodeHandleCaptureScreenshot(resp, &req_copy);
        should_emit_event = TRUE;
        break;
      default:
        resp->error_code = QERR_INVALID_OPCODE;
        RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "invalid_opcode");
        should_emit_event = TRUE;
        break;
    }
  }

  LARGE_INTEGER perf_end = KeQueryPerformanceCounter(NULL);
  ULONGLONG duration_ms = 0;
  if (perf_freq.QuadPart > 0 && perf_end.QuadPart >= perf_start.QuadPart) {
    duration_ms = (ULONGLONG)(((perf_end.QuadPart - perf_start.QuadPart) * 1000ULL) / perf_freq.QuadPart);
  }

  QuoodleRequestSecuritySignResponse(resp);

  if (should_emit_event) {
    QuoodleEventPipelineEmitOpcodeEvent(opcode, resp, duration_ms, req_copy.policy_hash);
  } else if (runtime_reason_code != NULL) {
    QuoodleEventPipelineMarkValidationReject();
    QuoodleEventPipelineEmitValidationReject(opcode, resp, runtime_reason_code, duration_ms, req_copy.policy_hash);
  }

  WdfRequestCompleteWithInformation(Request, STATUS_SUCCESS, sizeof(QUOODLE_IOCTL_RESPONSE));
}

static VOID QuoodleEvtDriverUnload(_In_ WDFDRIVER Driver) {
  UNREFERENCED_PARAMETER(Driver);
  QuoodleAppLockdownShutdown();
  DeleteUserSymbolicLinks();
  QuoodleRequestSecurityClearKey();
  QuoodleEventPipelineShutdown();
}

static NTSTATUS QuoodleCreateDevice(_Inout_ PWDFDEVICE_INIT* DeviceInitInOut, _Out_ WDFDEVICE* DeviceOut) {
  if (!DeviceInitInOut || !*DeviceInitInOut || !DeviceOut) {
    return STATUS_INVALID_PARAMETER;
  }

  PWDFDEVICE_INIT device_init = *DeviceInitInOut;

  WdfDeviceInitSetDeviceType(device_init, FILE_DEVICE_UNKNOWN);
  WdfDeviceInitSetCharacteristics(device_init, FILE_DEVICE_SECURE_OPEN, FALSE);

  UNICODE_STRING device_name;
  RtlInitUnicodeString(&device_name, QUOODLE_DEVICE_NAME);
  NTSTATUS status = WdfDeviceInitAssignName(device_init, &device_name);
  if (!NT_SUCCESS(status)) {
    return status;
  }

  WDFDEVICE device;
  status = WdfDeviceCreate(&device_init, WDF_NO_OBJECT_ATTRIBUTES, &device);
  if (!NT_SUCCESS(status)) {
    *DeviceInitInOut = device_init;
    return status;
  }
  *DeviceInitInOut = device_init;

  status = QuoodleEventPipelineInitialize(device);
  if (!NT_SUCCESS(status)) {
    goto CleanupDevice;
  }

  WDF_IO_QUEUE_CONFIG queue_config;
  WDF_OBJECT_ATTRIBUTES queue_attrs;
  WDF_OBJECT_ATTRIBUTES_INIT(&queue_attrs);
  queue_attrs.ExecutionLevel = WdfExecutionLevelPassive;
  WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(&queue_config, WdfIoQueueDispatchSequential);
  queue_config.EvtIoDeviceControl = QuoodleEvtIoDeviceControl;

  status = WdfIoQueueCreate(device, &queue_config, &queue_attrs, WDF_NO_HANDLE);
  if (!NT_SUCCESS(status)) {
    goto CleanupDevice;
  }

  *DeviceOut = device;
  return STATUS_SUCCESS;

CleanupDevice:
  WdfObjectDelete(device);
  return status;
}

NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath) {
  WDF_DRIVER_CONFIG config;
  WDF_DRIVER_CONFIG_INIT(&config, WDF_NO_EVENT_CALLBACK);
  config.DriverInitFlags |= WdfDriverInitNonPnpDriver;
  config.EvtDriverUnload = QuoodleEvtDriverUnload;

  WDFDRIVER driver = NULL;
  NTSTATUS status = WdfDriverCreate(DriverObject, RegistryPath, WDF_NO_OBJECT_ATTRIBUTES, &config, &driver);
  if (!NT_SUCCESS(status)) {
    return status;
  }

  UNICODE_STRING sddl;
  RtlInitUnicodeString(&sddl, L"D:P(A;;GA;;;SY)(A;;GA;;;BA)");
  PWDFDEVICE_INIT control_init = WdfControlDeviceInitAllocate(driver, &sddl);
  if (control_init == NULL) {
    return STATUS_INSUFFICIENT_RESOURCES;
  }

  WDFDEVICE control_device = NULL;
  status = QuoodleCreateDevice(&control_init, &control_device);
  if (!NT_SUCCESS(status)) {
    if (control_init != NULL) {
      WdfDeviceInitFree(control_init);
    }
    return status;
  }

  WdfControlFinishInitializing(control_device);

  status = CreateUserSymbolicLinks();
  if (!NT_SUCCESS(status)) {
    WdfObjectDelete(control_device);
    return status;
  }

  (VOID)QuoodleRequestSecurityLoadHmacKeyFromRegistry(RegistryPath);

  status = QuoodleAppLockdownInitialize();
  if (!NT_SUCCESS(status)) {
    DeleteUserSymbolicLinks();
    WdfObjectDelete(control_device);
    return status;
  }

  return STATUS_SUCCESS;
}
