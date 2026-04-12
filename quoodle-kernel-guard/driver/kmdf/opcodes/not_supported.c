#include "kmdf_opcode_common.h"
#include "kmdf_opcode_handlers.h"
#include <ntstrsafe.h>

VOID QuoodleOpcodeHandleNotSupported(_Out_ QUOODLE_IOCTL_RESPONSE* resp) {
  resp->status = 1;
  resp->error_code = QERR_NOT_SUPPORTED;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "not_supported");
  RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"not_supported\"}");
  resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
}


