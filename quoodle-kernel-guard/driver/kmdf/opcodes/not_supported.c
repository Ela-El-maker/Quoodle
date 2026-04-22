#include "kmdf_opcode_common.h"
#include "kmdf_opcode_handlers.h"
#include <ntstrsafe.h>

// Keep aligned with user-mode filesystem error mapping.
#define QERR_FS_ACCESS_DENIED 5204

static BOOLEAN q_is_ws(CHAR ch) {
  return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
}

static BOOLEAN q_is_path_sep(CHAR ch) {
  return ch == '\\' || ch == '/';
}

static CHAR q_ascii_lower(CHAR ch) {
  if (ch >= 'A' && ch <= 'Z') {
    return (CHAR)(ch + ('a' - 'A'));
  }
  return ch;
}

static BOOLEAN q_path_starts_with(
    _In_z_ const CHAR* path,
    _In_z_ const CHAR* prefix) {
  size_t i = 0;
  if (!path || !prefix) {
    return FALSE;
  }
  while (prefix[i] != '\0') {
    if (path[i] == '\0' || path[i] != prefix[i]) {
      return FALSE;
    }
    ++i;
  }
  return TRUE;
}

static BOOLEAN q_has_parent_reference_segment(_In_z_ const CHAR* path) {
  size_t len = 0;
  size_t start = 0;
  size_t i = 0;

  if (!path) {
    return FALSE;
  }

  len = q_opcode_strnlen_a(path, QUOODLE_MAX_PARAMS);
  for (i = 0; i <= len; ++i) {
    if (path[i] == '\\' || path[i] == '\0') {
      const size_t seg_len = i - start;
      if (seg_len == 2 && path[start] == '.' && path[start + 1] == '.') {
        return TRUE;
      }
      start = i + 1;
    }
  }

  return FALSE;
}

static BOOLEAN q_normalize_windows_path(
    _In_z_ const CHAR* raw_path,
    _Out_writes_(out_len) CHAR* out,
    _In_ size_t out_len) {
  const CHAR* src = raw_path;
  size_t src_len = 0;
  size_t in_i = 0;
  size_t out_i = 0;

  if (!raw_path || !out || out_len < 4) {
    return FALSE;
  }

  src_len = q_opcode_strnlen_a(src, QUOODLE_MAX_PARAMS);
  if (src_len == 0 || src_len >= QUOODLE_MAX_PARAMS) {
    return FALSE;
  }

  // Support user-mode and NT-style prefixes.
  if (src_len >= 4 && q_is_path_sep(src[0]) && src[1] == '?' && src[2] == '?' && q_is_path_sep(src[3])) {
    src += 4; // \??\
  } else if (src_len >= 3 && q_is_path_sep(src[0]) && src[1] == '?' && q_is_path_sep(src[2])) {
    src += 3; // \?\
  } else if (src_len >= 4 && q_is_path_sep(src[0]) && q_is_path_sep(src[1]) && src[2] == '?' && q_is_path_sep(src[3])) {
    src += 4; // \\?\
  } else if (src_len >= 5 && q_is_path_sep(src[0]) && q_is_path_sep(src[1]) && src[2] == '?' && src[3] == '?' && q_is_path_sep(src[4])) {
    src += 5; // \\??\
  }

  src_len = q_opcode_strnlen_a(src, QUOODLE_MAX_PARAMS);
  if (src_len == 0 || src_len >= QUOODLE_MAX_PARAMS) {
    return FALSE;
  }

  for (in_i = 0; in_i < src_len; ++in_i) {
    CHAR ch = src[in_i];
    if (ch == '\0') {
      break;
    }
    if (q_is_path_sep(ch)) {
      ch = '\\';
    } else {
      ch = q_ascii_lower(ch);
    }
    if (out_i + 1 >= out_len) {
      return FALSE;
    }
    out[out_i++] = ch;
  }
  out[out_i] = '\0';

  while (out_i > 3 && out[out_i - 1] == '\\') {
    out[--out_i] = '\0';
  }

  return out_i > 0;
}

typedef enum _Q_DELETE_POLICY_RESULT {
  Q_DELETE_POLICY_ALLOW = 0,
  Q_DELETE_POLICY_SCOPE_VIOLATION = 1,
  Q_DELETE_POLICY_PROTECTED_USERS_ROOT = 2,
  Q_DELETE_POLICY_PROTECTED_PROFILE_ROOT = 3,
} Q_DELETE_POLICY_RESULT;

static Q_DELETE_POLICY_RESULT q_validate_delete_policy(
    _In_z_ const CHAR* raw_path,
    _Out_writes_(normalized_len) CHAR* normalized_path,
    _In_ size_t normalized_len) {
  static const CHAR kUsersRoot[] = "c:\\users";
  const size_t users_root_len = sizeof(kUsersRoot) - 1;
  const CHAR* tail = NULL;

  if (!q_normalize_windows_path(raw_path, normalized_path, normalized_len)) {
    return Q_DELETE_POLICY_SCOPE_VIOLATION;
  }

  if (q_has_parent_reference_segment(normalized_path)) {
    return Q_DELETE_POLICY_SCOPE_VIOLATION;
  }

  // Require a canonical drive path rooted under C:\Users.
  if (q_opcode_strnlen_a(normalized_path, normalized_len) < 3) {
    return Q_DELETE_POLICY_SCOPE_VIOLATION;
  }
  if (normalized_path[1] != ':' || normalized_path[2] != '\\') {
    return Q_DELETE_POLICY_SCOPE_VIOLATION;
  }
  if (!q_path_starts_with(normalized_path, kUsersRoot)) {
    return Q_DELETE_POLICY_SCOPE_VIOLATION;
  }

  if (normalized_path[users_root_len] == '\0') {
    return Q_DELETE_POLICY_PROTECTED_USERS_ROOT;
  }
  if (normalized_path[users_root_len] != '\\') {
    return Q_DELETE_POLICY_SCOPE_VIOLATION;
  }

  tail = normalized_path + users_root_len + 1;
  if (*tail == '\0') {
    return Q_DELETE_POLICY_PROTECTED_USERS_ROOT;
  }

  // Block direct profile roots such as C:\Users\Felix.
  while (*tail != '\0') {
    if (*tail == '\\') {
      return Q_DELETE_POLICY_ALLOW;
    }
    ++tail;
  }

  return Q_DELETE_POLICY_PROTECTED_PROFILE_ROOT;
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

static BOOLEAN q_extract_string_param(
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req,
    _In_z_ const CHAR* key,
    _Out_writes_(out_len) CHAR* out,
    _In_ size_t out_len) {
  CHAR params[QUOODLE_MAX_PARAMS];
  CHAR token[64];
  size_t params_len = 0;
  size_t token_len = 0;
  size_t i = 0;

  if (!req || !key || !out || out_len < 2) {
    return FALSE;
  }

  out[0] = '\0';

  params_len = req->params_length;
  if (params_len >= sizeof(params)) {
    params_len = sizeof(params) - 1;
  }
  if (params_len == 0) {
    return FALSE;
  }

  if (!NT_SUCCESS(RtlStringCchPrintfA(token, sizeof(token), "\"%s\"", key))) {
    return FALSE;
  }
  token_len = q_opcode_strnlen_a(token, sizeof(token));
  if (token_len == 0) {
    return FALSE;
  }

  RtlZeroMemory(params, sizeof(params));
  RtlCopyMemory(params, req->params_json, params_len);
  params[params_len] = '\0';

  for (i = 0; i + token_len < params_len; ++i) {
    size_t j = 0;
    size_t cursor = 0;
    size_t out_cursor = 0;

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
    if (cursor >= params_len || params[cursor] != '"') {
      return FALSE;
    }
    cursor++;

    while (cursor < params_len && params[cursor] != '"') {
      if (params[cursor] == '\\' && cursor + 1 < params_len) {
        cursor++;
      }
      if (out_cursor + 1 >= out_len) {
        return FALSE;
      }
      out[out_cursor++] = params[cursor++];
    }

    if (cursor >= params_len || params[cursor] != '"') {
      return FALSE;
    }

    out[out_cursor] = '\0';
    return out_cursor > 0;
  }

  return FALSE;
}

static BOOLEAN q_extract_required_path_param(
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req,
    _Out_writes_(out_len) CHAR* out,
    _In_ size_t out_len) {
  return q_extract_string_param(req, "path", out, out_len);
}

static VOID q_opcode_fail_invalid_params(_Out_ QUOODLE_IOCTL_RESPONSE* resp) {
  resp->status = 1;
  resp->error_code = QERR_BAD_PAYLOAD;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "invalid_params_path_required");
  RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"failed\",\"reason\":\"invalid_params\"}");
  resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
}

static VOID q_opcode_deny_with_reason(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_z_ const CHAR* reason_code) {
  CHAR payload[QUOODLE_MAX_RESULT];
  NTSTATUS status = RtlStringCchPrintfA(
      payload,
      sizeof(payload),
      "{\"status\":\"denied\",\"kernel_mode\":true,\"reason\":\"%s\"}",
      reason_code);
  if (!NT_SUCCESS(status)) {
    resp->status = 1;
    resp->error_code = QERR_BAD_PAYLOAD;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "bad_payload");
    RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"failed\"}");
    resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
    return;
  }

  resp->status = 1;
  resp->error_code = QERR_FS_ACCESS_DENIED;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), reason_code);
  RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), payload);
  resp->result_length = (uint32_t)q_opcode_strnlen_a(resp->result_json, sizeof(resp->result_json));
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

static VOID q_opcode_handle_delete_authorized_collect(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req,
    _In_z_ const CHAR* snapshot_type) {
  CHAR path_value[QUOODLE_MAX_PARAMS];
  CHAR normalized_path[QUOODLE_MAX_PARAMS];
  Q_DELETE_POLICY_RESULT policy = Q_DELETE_POLICY_SCOPE_VIOLATION;

  if (!q_extract_required_path_param(req, path_value, sizeof(path_value))) {
    q_opcode_fail_invalid_params(resp);
    return;
  }

  policy = q_validate_delete_policy(path_value, normalized_path, sizeof(normalized_path));
  switch (policy) {
    case Q_DELETE_POLICY_ALLOW:
      q_opcode_handle_authorized_collect(resp, snapshot_type);
      return;
    case Q_DELETE_POLICY_PROTECTED_USERS_ROOT:
      q_opcode_deny_with_reason(resp, "fs_protected_root_users");
      return;
    case Q_DELETE_POLICY_PROTECTED_PROFILE_ROOT:
      q_opcode_deny_with_reason(resp, "fs_protected_root_profile");
      return;
    case Q_DELETE_POLICY_SCOPE_VIOLATION:
    default:
      q_opcode_deny_with_reason(resp, "fs_scope_violation");
      return;
  }
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

VOID QuoodleOpcodeHandleCreateDirectory(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  CHAR path_value[QUOODLE_MAX_PARAMS];
  if (!q_extract_required_path_param(req, path_value, sizeof(path_value))) {
    q_opcode_fail_invalid_params(resp);
    return;
  }

  q_opcode_handle_authorized_collect(resp, "create_directory");
}

VOID QuoodleOpcodeHandleCreateFile(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  CHAR path_value[QUOODLE_MAX_PARAMS];
  if (!q_extract_required_path_param(req, path_value, sizeof(path_value))) {
    q_opcode_fail_invalid_params(resp);
    return;
  }

  q_opcode_handle_authorized_collect(resp, "create_file");
}

VOID QuoodleOpcodeHandleDeleteFile(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  q_opcode_handle_delete_authorized_collect(resp, req, "delete_file");
}

VOID QuoodleOpcodeHandleDeleteDirectory(
    _Out_ QUOODLE_IOCTL_RESPONSE* resp,
    _In_opt_ const QUOODLE_IOCTL_REQUEST* req) {
  q_opcode_handle_delete_authorized_collect(resp, req, "delete_directory");
}


