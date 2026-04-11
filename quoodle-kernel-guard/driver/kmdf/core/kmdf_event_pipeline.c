#include <ntddk.h>
#include <ntstrsafe.h>
#include <wdf.h>

#include "kmdf_event_pipeline.h"

#define QUOODLE_EVENT_RING_SIZE 16

static volatile LONGLONG g_event_counter = 0;
static volatile LONGLONG g_event_dropped = 0;
static volatile LONGLONG g_validation_rejects = 0;
static volatile LONGLONG g_runtime_internal_errors = 0;

static QUOODLE_KERNEL_EVENT g_event_ring[QUOODLE_EVENT_RING_SIZE];
static ULONG g_event_head = 0;
static ULONG g_event_tail = 0;
static ULONG g_event_count = 0;
static WDFSPINLOCK g_event_lock = NULL;
static WDFQUEUE g_wait_queue = NULL;

static SIZE_T qep_strnlen_a(const CHAR* s, SIZE_T max_len) {
  SIZE_T len = 0;
  if (!s) {
    return 0;
  }
  while (len < max_len && s[len] != '\0') {
    len++;
  }
  return len;
}

static uint64_t qep_unix_timestamp_seconds(void) {
  LARGE_INTEGER system_time;
  KeQuerySystemTime(&system_time);
  const LONGLONG epoch_delta = 116444736000000000LL;
  if (system_time.QuadPart < epoch_delta) {
    return 0;
  }
  return (uint64_t)((system_time.QuadPart - epoch_delta) / 10000000ULL);
}

static VOID qep_init_kernel_event(_Out_ QUOODLE_KERNEL_EVENT* evt, _In_ uint32_t type, _In_opt_ const CHAR* payload_json) {
  RtlZeroMemory(evt, sizeof(*evt));
  evt->event_id = (uint64_t)InterlockedIncrement64(&g_event_counter);
  evt->event_type = type;
  evt->timestamp_unix = qep_unix_timestamp_seconds();
  if (payload_json && *payload_json) {
    SIZE_T max_len = sizeof(evt->payload_json) - 1;
    SIZE_T len = qep_strnlen_a(payload_json, max_len);
    if (len > max_len) {
      len = max_len;
    }
    RtlCopyMemory(evt->payload_json, payload_json, len);
    evt->payload_json[len] = '\0';
    evt->payload_length = (uint32_t)len;
  }
}

static VOID qep_push_kernel_event(_In_ const QUOODLE_KERNEL_EVENT* evt) {
  if (!g_event_lock) {
    return;
  }

  WdfSpinLockAcquire(g_event_lock);
  if (g_event_count == QUOODLE_EVENT_RING_SIZE) {
    g_event_tail = (g_event_tail + 1) % QUOODLE_EVENT_RING_SIZE;
    g_event_count--;
    InterlockedIncrement64(&g_event_dropped);
  }
  g_event_ring[g_event_head] = *evt;
  g_event_head = (g_event_head + 1) % QUOODLE_EVENT_RING_SIZE;
  g_event_count++;
  WdfSpinLockRelease(g_event_lock);
}

static VOID qep_deliver_or_queue_kernel_event(_In_ const QUOODLE_KERNEL_EVENT* evt) {
  if (g_wait_queue) {
    WDFREQUEST wait_request = NULL;
    NTSTATUS status = WdfIoQueueRetrieveNextRequest(g_wait_queue, &wait_request);
    if (NT_SUCCESS(status) && wait_request) {
      QUOODLE_KERNEL_EVENT* out = NULL;
      SIZE_T out_len = 0;
      status = WdfRequestRetrieveOutputBuffer(wait_request, sizeof(QUOODLE_KERNEL_EVENT), (PVOID*)&out, &out_len);
      if (NT_SUCCESS(status) && out && out_len >= sizeof(QUOODLE_KERNEL_EVENT)) {
        RtlCopyMemory(out, evt, sizeof(*evt));
        WdfRequestCompleteWithInformation(wait_request, STATUS_SUCCESS, sizeof(QUOODLE_KERNEL_EVENT));
        return;
      }
      InterlockedIncrement64(&g_runtime_internal_errors);
      WdfRequestComplete(wait_request, STATUS_INVALID_PARAMETER);
    }
  }

  qep_push_kernel_event(evt);
}

static const CHAR* qep_opcode_to_string(_In_ QUOODLE_OPCODE opcode) {
  switch (opcode) {
    case QOP_EXEC_LOCK_SCREEN:
      return "LOCK_SCREEN";
    case QOP_EXEC_REBOOT:
      return "REBOOT";
    case QOP_EXEC_SHUTDOWN:
      return "SHUTDOWN";
    case QOP_EXEC_LOGOUT:
      return "LOGOUT";
    case QOP_EXEC_PING:
      return "PING";
    case QOP_EXEC_COLLECT_SYSTEM_INFO:
      return "COLLECT_SYSTEM_INFO";
    case QOP_EXEC_GET_PROCESS_LIST:
      return "GET_PROCESS_LIST";
    case QOP_EXEC_VALIDATE_UPDATE_PACKAGE:
      return "VALIDATE_UPDATE_PACKAGE";
    case QOP_STAGE_UPDATE:
      return "STAGE_UPDATE";
    case QOP_COMMIT_UPDATE:
      return "COMMIT_UPDATE";
    case QOP_ROLLBACK_UPDATE:
      return "ROLLBACK_UPDATE";
    case QOP_EXEC_RUN_ATTESTATION:
      return "RUN_ATTESTATION";
    case QOP_EXEC_RUN_TAMPER_CHECK:
      return "RUN_TAMPER_CHECK";
    case QOP_EXEC_SELF_REPAIR:
      return "SELF_REPAIR";
    default:
      return "UNKNOWN";
  }
}

static const CHAR* qep_opcode_category(_In_ QUOODLE_OPCODE opcode) {
  switch (opcode) {
    case QOP_EXEC_RUN_ATTESTATION:
      return "attestation";
    case QOP_EXEC_RUN_TAMPER_CHECK:
    case QOP_EXEC_SELF_REPAIR:
      return "integrity";
    case QOP_EXEC_VALIDATE_UPDATE_PACKAGE:
    case QOP_STAGE_UPDATE:
    case QOP_COMMIT_UPDATE:
    case QOP_ROLLBACK_UPDATE:
      return "update";
    default:
      return "exec";
  }
}

static const CHAR* qep_opcode_subtype(_In_ QUOODLE_OPCODE opcode) {
  switch (opcode) {
    case QOP_EXEC_RUN_ATTESTATION:
      return "attestation_check";
    case QOP_EXEC_RUN_TAMPER_CHECK:
    case QOP_EXEC_SELF_REPAIR:
      return "integrity_check";
    case QOP_EXEC_VALIDATE_UPDATE_PACKAGE:
      return "update_validate";
    case QOP_STAGE_UPDATE:
      return "update_stage";
    case QOP_COMMIT_UPDATE:
      return "update_commit";
    case QOP_ROLLBACK_UPDATE:
      return "update_rollback";
    default:
      return "opcode";
  }
}

static QUOODLE_KERNEL_EVENT_TYPE qep_event_type_for_opcode(_In_ QUOODLE_OPCODE opcode) {
  switch (opcode) {
    case QOP_EXEC_RUN_ATTESTATION:
      return QKEVENT_TYPE_ATTESTATION;
    case QOP_EXEC_RUN_TAMPER_CHECK:
    case QOP_EXEC_SELF_REPAIR:
      return QKEVENT_TYPE_INTEGRITY;
    case QOP_EXEC_VALIDATE_UPDATE_PACKAGE:
    case QOP_STAGE_UPDATE:
    case QOP_COMMIT_UPDATE:
    case QOP_ROLLBACK_UPDATE:
      return QKEVENT_TYPE_UPDATE;
    default:
      return QKEVENT_TYPE_OPCODE;
  }
}

static ULONG qep_current_queue_depth(VOID) {
  ULONG depth = 0;
  if (!g_event_lock) {
    return 0;
  }

  WdfSpinLockAcquire(g_event_lock);
  depth = g_event_count;
  WdfSpinLockRelease(g_event_lock);
  return depth;
}

static VOID qep_emit_kernel_category_event(
    _In_ QUOODLE_KERNEL_EVENT_TYPE event_type,
    _In_opt_ const CHAR* category,
    _In_opt_ const CHAR* subtype,
    _In_opt_ const CHAR* severity,
    _In_opt_ const CHAR* decision,
    _In_opt_ const CHAR* reason_code,
    _In_opt_ const CHAR* opcode,
    _In_ ULONG error_code,
    _In_ ULONGLONG duration_ms,
    _In_opt_ const CHAR* policy_ref) {
  CHAR payload[QUOODLE_MAX_EVENT_PAYLOAD];
  ULONGLONG dropped = (ULONGLONG)InterlockedCompareExchange64(&g_event_dropped, 0, 0);
  ULONGLONG validation_rejects = (ULONGLONG)InterlockedCompareExchange64(&g_validation_rejects, 0, 0);
  ULONGLONG runtime_internal_errors = (ULONGLONG)InterlockedCompareExchange64(&g_runtime_internal_errors, 0, 0);
  ULONG queue_depth = qep_current_queue_depth();

  if (!category) category = "runtime";
  if (!subtype) subtype = "event";
  if (!severity) severity = "info";
  if (!decision) decision = "observe";
  if (!reason_code) reason_code = "none";
  if (!opcode) opcode = "UNKNOWN";
  if (!policy_ref) policy_ref = "";

  (void)RtlStringCchPrintfA(payload,
                            sizeof(payload),
                            "{\"category\":\"%s\",\"subtype\":\"%s\",\"severity\":\"%s\",\"decision\":\"%s\","
                            "\"reason_code\":\"%s\",\"opcode\":\"%s\",\"error_code\":%u,\"duration_ms\":%I64u,"
                            "\"queue_depth\":%u,\"drop_count\":%I64u,\"validation_reject_count\":%I64u,"
                            "\"runtime_error_count\":%I64u,\"policy_ref\":\"%s\",\"masked_fields\":[]}",
                            category,
                            subtype,
                            severity,
                            decision,
                            reason_code,
                            opcode,
                            error_code,
                            duration_ms,
                            queue_depth,
                            dropped,
                            validation_rejects,
                            runtime_internal_errors,
                            policy_ref);

  QUOODLE_KERNEL_EVENT evt;
  qep_init_kernel_event(&evt, event_type, payload);
  qep_deliver_or_queue_kernel_event(&evt);
}

NTSTATUS QuoodleEventPipelineInitialize(_In_ WDFDEVICE device) {
  NTSTATUS status;

  status = WdfSpinLockCreate(WDF_NO_OBJECT_ATTRIBUTES, &g_event_lock);
  if (!NT_SUCCESS(status)) {
    return status;
  }

  g_event_head = 0;
  g_event_tail = 0;
  g_event_count = 0;
  g_event_counter = 0;
  g_event_dropped = 0;
  g_validation_rejects = 0;
  g_runtime_internal_errors = 0;

  WDF_IO_QUEUE_CONFIG wait_queue_config;
  WDF_OBJECT_ATTRIBUTES wait_queue_attrs;
  WDF_OBJECT_ATTRIBUTES_INIT(&wait_queue_attrs);
  wait_queue_attrs.ExecutionLevel = WdfExecutionLevelPassive;
  WDF_IO_QUEUE_CONFIG_INIT(&wait_queue_config, WdfIoQueueDispatchManual);

  status = WdfIoQueueCreate(device, &wait_queue_config, &wait_queue_attrs, &g_wait_queue);
  if (!NT_SUCCESS(status)) {
    g_event_lock = NULL;
    return status;
  }

  return STATUS_SUCCESS;
}

VOID QuoodleEventPipelineShutdown(VOID) {
  g_wait_queue = NULL;
  g_event_lock = NULL;
}

BOOLEAN QuoodleEventPipelineTryPop(_Out_ QUOODLE_KERNEL_EVENT* out) {
  BOOLEAN has_event = FALSE;
  if (!g_event_lock || !out) {
    return FALSE;
  }

  WdfSpinLockAcquire(g_event_lock);
  if (g_event_count > 0) {
    *out = g_event_ring[g_event_tail];
    g_event_tail = (g_event_tail + 1) % QUOODLE_EVENT_RING_SIZE;
    g_event_count--;
    has_event = TRUE;
  }
  WdfSpinLockRelease(g_event_lock);
  return has_event;
}

NTSTATUS QuoodleEventPipelinePendWaitRequest(_In_ WDFREQUEST request) {
  if (!g_wait_queue) {
    return STATUS_INVALID_DEVICE_STATE;
  }
  return WdfRequestForwardToIoQueue(request, g_wait_queue);
}

VOID QuoodleEventPipelineEmitOpcodeEvent(
    _In_ QUOODLE_OPCODE opcode,
    _In_ const QUOODLE_IOCTL_RESPONSE* resp,
    _In_ ULONGLONG duration_ms,
    _In_opt_ const CHAR* policy_ref) {
  const CHAR* status = resp->status == 0 ? "ok" : "error";
  const CHAR* opcode_str = qep_opcode_to_string(opcode);
  const CHAR* category = qep_opcode_category(opcode);
  const CHAR* subtype = qep_opcode_subtype(opcode);
  const CHAR* severity = resp->status == 0 ? "info" : "high";
  const CHAR* decision = resp->status == 0 ? "allow" : "deny";

  qep_emit_kernel_category_event(
      qep_event_type_for_opcode(opcode),
      category,
      subtype,
      severity,
      decision,
      status,
      opcode_str,
      resp->error_code,
      duration_ms,
      policy_ref);
}

VOID QuoodleEventPipelineMarkValidationReject(VOID) {
  InterlockedIncrement64(&g_validation_rejects);
}

VOID QuoodleEventPipelineEmitValidationReject(
    _In_ QUOODLE_OPCODE opcode,
    _In_ const QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const CHAR* reason_code,
    _In_ ULONGLONG duration_ms,
    _In_opt_ const CHAR* policy_ref) {
  const CHAR* opcode_str = qep_opcode_to_string(opcode);

  qep_emit_kernel_category_event(
      QKEVENT_TYPE_RUNTIME,
      "runtime",
      "validation_reject",
      "medium",
      "reject",
      reason_code,
      opcode_str,
      resp->error_code,
      duration_ms,
      policy_ref);
}