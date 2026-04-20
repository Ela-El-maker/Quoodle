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

static BOOLEAN qep_json_escape(
    _In_reads_or_z_(in_len) const CHAR* in,
    _In_ SIZE_T in_len,
    _Out_writes_(out_len) CHAR* out,
    _In_ SIZE_T out_len) {
  SIZE_T i = 0;
  SIZE_T j = 0;

  if (!out || out_len < 2) {
    return FALSE;
  }
  out[0] = '\0';

  if (!in) {
    return TRUE;
  }

  for (i = 0; i < in_len && in[i] != '\0'; ++i) {
    const UCHAR c = (UCHAR)in[i];
    if (c == '\\' || c == '"') {
      if (j + 2 >= out_len) {
        return FALSE;
      }
      out[j++] = '\\';
      out[j++] = (CHAR)c;
      continue;
    }
    if (c < 0x20) {
      if (j + 6 >= out_len) {
        return FALSE;
      }
      out[j++] = '\\';
      out[j++] = 'u';
      out[j++] = '0';
      out[j++] = '0';
      out[j++] = "0123456789abcdef"[(c >> 4) & 0x0F];
      out[j++] = "0123456789abcdef"[c & 0x0F];
      continue;
    }
    if (j + 1 >= out_len) {
      return FALSE;
    }
    out[j++] = (CHAR)c;
  }

  out[j] = '\0';
  return TRUE;
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
    case QOP_EXEC_KILL_PROCESS:
      return "KILL_PROCESS";
    case QOP_OBS_LIST_PROCESSES:
      return "LIST_PROCESSES";
    case QOP_OBS_LIST_SERVICES:
      return "LIST_SERVICES";
    case QOP_OBS_LIST_CONNECTIONS:
      return "LIST_CONNECTIONS";
    case QOP_OBS_LIST_MOUNTS:
      return "LIST_MOUNTS";
    case QOP_OBS_NETWORK_INFO:
      return "NETWORK_INFO";
    case QOP_OBS_GET_ACTIVE_WINDOW:
      return "GET_ACTIVE_WINDOW";
    case QOP_SEC_APPLOCK_REPLACE_POLICY:
      return "SEC_APPLOCK_REPLACE_POLICY";
    case QOP_SEC_APPLOCK_GET_STATUS:
      return "SEC_APPLOCK_GET_STATUS";
    case QOP_SEC_APPLOCK_CLEAR_POLICY:
      return "SEC_APPLOCK_CLEAR_POLICY";
    case QOP_EXEC_VALIDATE_UPDATE_PACKAGE:
      return "VALIDATE_UPDATE_PACKAGE";
    case QOP_EXEC_CAPTURE_SCREENSHOT:
      return "CAPTURE_SCREENSHOT";
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
    case QOP_SEC_APPLOCK_REPLACE_POLICY:
    case QOP_SEC_APPLOCK_GET_STATUS:
    case QOP_SEC_APPLOCK_CLEAR_POLICY:
      return "security";
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
    case QOP_SEC_APPLOCK_REPLACE_POLICY:
      return "applock_replace_policy";
    case QOP_SEC_APPLOCK_GET_STATUS:
      return "applock_get_status";
    case QOP_SEC_APPLOCK_CLEAR_POLICY:
      return "applock_clear_policy";
    case QOP_EXEC_KILL_PROCESS:
      return "process_control";
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

VOID QuoodleEventPipelineEmitAppBlockEvent(
    _In_opt_ const CHAR* rule_id,
    _In_opt_ const CHAR* match_type,
    _In_opt_ const CHAR* matched_value,
    _In_opt_ const CHAR* image_path,
    _In_opt_ const CHAR* image_name,
    _In_opt_ const CHAR* reason_code,
    _In_opt_ const CHAR* policy_version,
    _In_opt_ const CHAR* policy_hash,
    _In_ ULONG session_id) {
  CHAR payload[QUOODLE_MAX_EVENT_PAYLOAD];
  CHAR escaped_rule_id[96];
  CHAR escaped_match_type[64];
  CHAR escaped_matched_value[320];
  CHAR escaped_image_path[320];
  CHAR escaped_image_name[128];
  CHAR escaped_reason_code[96];
  CHAR escaped_policy_version[96];
  CHAR escaped_policy_hash[160];

  if (!rule_id) rule_id = "";
  if (!match_type) match_type = "";
  if (!matched_value) matched_value = "";
  if (!image_path) image_path = "";
  if (!image_name) image_name = "";
  if (!reason_code) reason_code = "blocked_policy";
  if (!policy_version) policy_version = "";
  if (!policy_hash) policy_hash = "";

  if (!qep_json_escape(rule_id, qep_strnlen_a(rule_id, 80), escaped_rule_id, sizeof(escaped_rule_id))) return;
  if (!qep_json_escape(match_type, qep_strnlen_a(match_type, 32), escaped_match_type, sizeof(escaped_match_type))) return;
  if (!qep_json_escape(matched_value, qep_strnlen_a(matched_value, 260), escaped_matched_value, sizeof(escaped_matched_value))) return;
  if (!qep_json_escape(image_path, qep_strnlen_a(image_path, 260), escaped_image_path, sizeof(escaped_image_path))) return;
  if (!qep_json_escape(image_name, qep_strnlen_a(image_name, 96), escaped_image_name, sizeof(escaped_image_name))) return;
  if (!qep_json_escape(reason_code, qep_strnlen_a(reason_code, 80), escaped_reason_code, sizeof(escaped_reason_code))) return;
  if (!qep_json_escape(policy_version, qep_strnlen_a(policy_version, 80), escaped_policy_version, sizeof(escaped_policy_version))) return;
  if (!qep_json_escape(policy_hash, qep_strnlen_a(policy_hash, 140), escaped_policy_hash, sizeof(escaped_policy_hash))) return;

  (void)RtlStringCchPrintfA(
      payload,
      sizeof(payload),
      "{\"event_type\":\"app_blocked\",\"category\":\"exec\",\"subtype\":\"app_blocked\","
      "\"severity\":\"high\",\"decision\":\"deny\",\"reason_code\":\"%s\","
      "\"rule_id\":\"%s\",\"match_type\":\"%s\",\"matched_value\":\"%s\","
      "\"image_path\":\"%s\",\"image_name\":\"%s\",\"session_id\":%u,"
      "\"policy_version\":\"%s\",\"policy_hash\":\"%s\",\"masked_fields\":[]}",
      escaped_reason_code,
      escaped_rule_id,
      escaped_match_type,
      escaped_matched_value,
      escaped_image_path,
      escaped_image_name,
      session_id,
      escaped_policy_version,
      escaped_policy_hash);

  QUOODLE_KERNEL_EVENT evt;
  qep_init_kernel_event(&evt, QKEVENT_TYPE_RUNTIME, payload);
  qep_deliver_or_queue_kernel_event(&evt);
}
