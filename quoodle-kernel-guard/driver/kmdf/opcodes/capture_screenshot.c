#include "kmdf_opcode_common.h"
#include "kmdf_opcode_handlers.h"
#include <ntstrsafe.h>

VOID QuoodleOpcodeHandleCaptureScreenshot(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  UNREFERENCED_PARAMETER(req);

  resp->status = 0;
  resp->error_code = 0;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "");
  q_opcode_build_exec_id(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
  RtlStringCchCopyA(
      resp->result_json,
      sizeof(resp->result_json),
      "{\"status\":\"authorized\",\"kernel_mode\":true,\"snapshot_type\":\"screenshot\"}");
  resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
}
