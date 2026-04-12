#include "kmdf_opcode_common.h"
#include "kmdf_opcode_handlers.h"
#include <ntstrsafe.h>

VOID QuoodleOpcodeHandleReboot(_Out_ QUOODLE_IOCTL_RESPONSE* resp) {
  NTSTATUS status = NtShutdownSystem(QuoodleShutdownReboot);
  if (NT_SUCCESS(status)) {
    resp->status = 0;
    resp->error_code = 0;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "");
    q_opcode_build_exec_id(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
    RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"ok\",\"message\":\"reboot_initiated\"}");
    resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
  } else {
    resp->status = 1;
    resp->error_code = 5002;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "reboot_failed");
  }
}

