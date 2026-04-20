#include "kmdf_opcode_common.h"
#include "kmdf_opcode_handlers.h"
#include <ntstrsafe.h>

static BOOLEAN q_is_ws(CHAR ch) {
  return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
}

static BOOLEAN q_extract_pid_param(
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req,
    _Out_ ULONG* pid_out) {
  const CHAR token[] = "\"pid\"";
  CHAR params[QUOODLE_MAX_PARAMS];
  size_t params_len = 0;
  size_t token_len = sizeof(token) - 1;
  size_t i = 0;

  if (!req || !pid_out) {
    return FALSE;
  }
  *pid_out = 0;

  params_len = req->params_length;
  if (params_len >= sizeof(params)) {
    params_len = sizeof(params) - 1;
  }
  if (params_len == 0) {
    return FALSE;
  }

  RtlZeroMemory(params, sizeof(params));
  RtlCopyMemory(params, req->params_json, params_len);
  params[params_len] = '\0';

  for (i = 0; i + token_len < params_len; ++i) {
    size_t j = 0;
    size_t cursor = 0;
    ULONGLONG parsed = 0;
    BOOLEAN has_digits = FALSE;

    for (j = 0; j < token_len; ++j) {
      if (params[i + j] != token[j]) {
        break;
      }
    }
    if (j != token_len) {
      continue;
    }

    cursor = i + token_len;
    while (cursor < params_len && q_is_ws(params[cursor])) {
      cursor++;
    }
    if (cursor >= params_len || params[cursor] != ':') {
      continue;
    }
    cursor++;
    while (cursor < params_len && q_is_ws(params[cursor])) {
      cursor++;
    }
    while (cursor < params_len && params[cursor] >= '0' && params[cursor] <= '9') {
      has_digits = TRUE;
      parsed = (parsed * 10) + (ULONGLONG)(params[cursor] - '0');
      if (parsed > 0xFFFFFFFFULL) {
        return FALSE;
      }
      cursor++;
    }

    if (!has_digits || parsed < 2) {
      return FALSE;
    }

    *pid_out = (ULONG)parsed;
    return TRUE;
  }

  return FALSE;
}

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

VOID QuoodleOpcodeHandleKillProcess(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  ULONG pid = 0;
  HANDLE process_handle = NULL;
  OBJECT_ATTRIBUTES attrs;
  CLIENT_ID client_id;
  NTSTATUS status;
  CHAR payload[128];

  if (!q_extract_pid_param(req, &pid)) {
    resp->status = 1;
    resp->error_code = QERR_BAD_PAYLOAD;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "invalid_params_pid_required");
    RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"failed\",\"reason\":\"invalid_params\"}");
    resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
    return;
  }

  InitializeObjectAttributes(&attrs, NULL, OBJ_KERNEL_HANDLE, NULL, NULL);
  client_id.UniqueProcess = (HANDLE)(ULONG_PTR)pid;
  client_id.UniqueThread = NULL;

  status = ZwOpenProcess(&process_handle, PROCESS_TERMINATE, &attrs, &client_id);
  if (!NT_SUCCESS(status) || process_handle == NULL) {
    resp->status = 1;
    resp->error_code = 5201;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "process_open_failed");
    RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"failed\",\"reason\":\"process_open_failed\"}");
    resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
    return;
  }

  status = ZwTerminateProcess(process_handle, STATUS_SUCCESS);
  ZwClose(process_handle);
  if (!NT_SUCCESS(status)) {
    resp->status = 1;
    resp->error_code = 5202;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "process_terminate_failed");
    RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"failed\",\"reason\":\"process_terminate_failed\"}");
    resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
    return;
  }

  resp->status = 0;
  resp->error_code = 0;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "");
  q_opcode_build_exec_id(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
  (void)RtlStringCchPrintfA(payload, sizeof(payload), "{\"status\":\"ok\",\"pid\":%u,\"action\":\"terminated\"}", pid);
  RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), payload);
  resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
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

VOID QuoodleOpcodeHandleListFiles(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  UNREFERENCED_PARAMETER(req);
  q_opcode_handle_authorized_collect(resp, "list_files");
}

VOID QuoodleOpcodeHandleDownloadFile(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  UNREFERENCED_PARAMETER(req);
  q_opcode_handle_authorized_collect(resp, "download_file");
}


