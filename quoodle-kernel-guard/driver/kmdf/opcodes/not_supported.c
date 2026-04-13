#include "kmdf_opcode_common.h"
#include "kmdf_opcode_handlers.h"
#include <ntstrsafe.h>

static VOID q_opcode_handle_authorized_collect(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_z_ const CHAR* snapshot_type) {
  CHAR payload[QUOODLE_MAX_RESULT];
  NTSTATUS status = RtlStringCchPrintfA(
      payload,
      sizeof(payload),
      "{\"status\":\"authorized\",\"kernel_mode\":true,\"snapshot_type\":\"%s\"}",
      snapshot_type);
  if (!NT_SUCCESS(status)) {
    resp->status = 1;
    resp->error_code = QERR_BAD_PAYLOAD;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "bad_payload");
    RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"failed\"}");
    resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
    return;
  }

  resp->status = 0;
  resp->error_code = 0;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "");
  q_opcode_build_exec_id(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
  RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), payload);
  resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
}

VOID QuoodleOpcodeHandleNotSupported(_Out_ QUOODLE_IOCTL_RESPONSE* resp) {
  resp->status = 1;
  resp->error_code = QERR_NOT_SUPPORTED;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "not_supported");
  RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"not_supported\"}");
  resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
}

VOID QuoodleOpcodeHandleGetProcessList(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  UNREFERENCED_PARAMETER(req);
  q_opcode_handle_authorized_collect(resp, "list_processes");
}

VOID QuoodleOpcodeHandleListServices(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  UNREFERENCED_PARAMETER(req);
  q_opcode_handle_authorized_collect(resp, "list_services");
}

VOID QuoodleOpcodeHandleListConnections(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  UNREFERENCED_PARAMETER(req);
  q_opcode_handle_authorized_collect(resp, "list_connections");
}

VOID QuoodleOpcodeHandleListMounts(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  UNREFERENCED_PARAMETER(req);
  q_opcode_handle_authorized_collect(resp, "list_mounts");
}

VOID QuoodleOpcodeHandleNetworkInfo(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  UNREFERENCED_PARAMETER(req);
  q_opcode_handle_authorized_collect(resp, "network_info");
}

VOID QuoodleOpcodeHandleGetActiveWindow(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  UNREFERENCED_PARAMETER(req);
  q_opcode_handle_authorized_collect(resp, "get_active_window");
}


