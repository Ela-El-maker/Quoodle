#include "kmdf_opcode_common.h"
#include "kmdf_opcode_handlers.h"
#include <ntstrsafe.h>

VOID QuoodleOpcodeHandleLockScreen(_Out_ QUOODLE_IOCTL_RESPONSE* resp) {
  const CHAR* payload = "{\"status\":\"authorized\",\"kernel_mode\":true,\"snapshot_type\":\"lock_screen\"}";
  size_t payload_len = 0;

  resp->status = 0;
  resp->error_code = 0;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "");
  q_opcode_build_exec_id(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
  RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), payload);
  if (NT_SUCCESS(RtlStringCchLengthA(payload, sizeof(resp->result_json), &payload_len))) {
    resp->result_length = (uint32_t)payload_len;
  } else {
    resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
  }
}

