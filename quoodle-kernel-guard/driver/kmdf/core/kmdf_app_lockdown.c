#include <ntddk.h>
#include <ntstrsafe.h>

#include "kmdf_app_lockdown.h"
#include "kmdf_event_pipeline.h"

#define QAPP_MAX_RULES 128
#define QAPP_MAX_RULE_ID 64
#define QAPP_MAX_RULE_VALUE 260
#define QAPP_MAX_POLICY_VERSION 64
#define QAPP_MAX_POLICY_HASH 128
#define QAPP_MAX_MODE 16
#define QAPP_MAX_FAIL_MODE 16
#define QAPP_MAX_PARSE_BUFFER QUOODLE_MAX_PARAMS
#define QAPP_MAX_DEDUPE_SLOTS 64
#define QAPP_TAG_POLICY 'PpAQ'

typedef enum _QAPP_MATCH_TYPE {
  QAPP_MATCH_NONE = 0,
  QAPP_MATCH_BASENAME = 1,
  QAPP_MATCH_FULL_PATH = 2,
} QAPP_MATCH_TYPE;

typedef struct _QAPP_RULE {
  BOOLEAN used;
  CHAR rule_id[QAPP_MAX_RULE_ID];
  QAPP_MATCH_TYPE match_type;
  CHAR value[QAPP_MAX_RULE_VALUE];
  ULONG priority;
  BOOLEAN has_expires_at;
  ULONGLONG expires_at_unix;
} QAPP_RULE;

typedef struct _QAPP_POLICY {
  BOOLEAN configured;
  BOOLEAN enabled;
  CHAR mode[QAPP_MAX_MODE];
  CHAR fail_mode[QAPP_MAX_FAIL_MODE];
  CHAR policy_version[QAPP_MAX_POLICY_VERSION];
  CHAR policy_hash[QAPP_MAX_POLICY_HASH];
  ULONG event_dedupe_sec;
  ULONG rule_count;
  QAPP_RULE rules[QAPP_MAX_RULES];
} QAPP_POLICY;

typedef struct _QAPP_DEDUPE_SLOT {
  ULONGLONG key_hash;
  ULONGLONG expires_at_unix;
} QAPP_DEDUPE_SLOT;

static EX_PUSH_LOCK g_policy_lock = {0};
static QAPP_POLICY g_policy;
static volatile LONG g_policy_generation = 0;
static BOOLEAN g_callback_registered = FALSE;
static NTSTATUS g_callback_register_status = STATUS_NOT_SUPPORTED;
static KSPIN_LOCK g_dedupe_lock;
static QAPP_DEDUPE_SLOT g_dedupe_slots[QAPP_MAX_DEDUPE_SLOTS];

static const CHAR* g_critical_allowlist[] = {
    "smss.exe",
    "csrss.exe",
    "wininit.exe",
    "winlogon.exe",
    "services.exe",
    "lsass.exe",
    "svchost.exe",
    "dwm.exe",
    "explorer.exe",
    "agent.exe",
    "quoodle-agent.exe",
    "quoodle-agent-windows.exe",
};

static SIZE_T qapp_strnlen(_In_reads_or_z_(max_len) const CHAR* s, _In_ SIZE_T max_len) {
  SIZE_T len = 0;
  if (!s) {
    return 0;
  }
  while (len < max_len && s[len] != '\0') {
    len++;
  }
  return len;
}

static ULONGLONG qapp_now_unix_seconds(VOID) {
  LARGE_INTEGER system_time;
  const LONGLONG epoch_delta = 116444736000000000LL;
  KeQuerySystemTime(&system_time);
  if (system_time.QuadPart < epoch_delta) {
    return 0;
  }
  return (ULONGLONG)((system_time.QuadPart - epoch_delta) / 10000000ULL);
}

static VOID qapp_copy_ascii(_Out_writes_(dst_len) CHAR* dst, _In_ SIZE_T dst_len, _In_opt_ const CHAR* src) {
  if (!dst || dst_len == 0) {
    return;
  }
  if (!src) {
    dst[0] = '\0';
    return;
  }
  (void)RtlStringCchCopyNA(dst, dst_len, src, dst_len - 1);
  dst[dst_len - 1] = '\0';
}

static VOID qapp_normalize_ascii_path(_Inout_updates_(len) CHAR* value, _In_ SIZE_T len) {
  SIZE_T i = 0;
  if (!value || len == 0) {
    return;
  }
  while (i < len && value[i] != '\0') {
    CHAR ch = value[i];
    if (ch >= 'A' && ch <= 'Z') {
      value[i] = (CHAR)(ch - 'A' + 'a');
    } else if (ch == '/') {
      value[i] = '\\';
    }
    i++;
  }
}

static BOOLEAN qapp_ascii_equals(_In_opt_ const CHAR* a, _In_opt_ const CHAR* b) {
  SIZE_T i = 0;
  if (!a || !b) {
    return FALSE;
  }
  while (a[i] != '\0' && b[i] != '\0') {
    if (a[i] != b[i]) {
      return FALSE;
    }
    i++;
  }
  return a[i] == '\0' && b[i] == '\0';
}

static BOOLEAN qapp_ascii_starts_with(_In_ const CHAR* value, _In_ const CHAR* prefix) {
  SIZE_T i = 0;
  if (!value || !prefix) {
    return FALSE;
  }
  while (prefix[i] != '\0') {
    if (value[i] != prefix[i]) {
      return FALSE;
    }
    i++;
  }
  return TRUE;
}

static BOOLEAN qapp_ascii_ends_with(_In_ const CHAR* value, _In_ const CHAR* suffix) {
  SIZE_T value_len;
  SIZE_T suffix_len;
  if (!value || !suffix) {
    return FALSE;
  }
  value_len = qapp_strnlen(value, QAPP_MAX_RULE_VALUE * 2);
  suffix_len = qapp_strnlen(suffix, QAPP_MAX_RULE_VALUE * 2);
  if (suffix_len == 0 || suffix_len > value_len) {
    return FALSE;
  }
  return qapp_ascii_equals(value + (value_len - suffix_len), suffix);
}

static VOID qapp_extract_basename(_In_opt_ const CHAR* path, _Out_writes_(out_len) CHAR* out, _In_ SIZE_T out_len) {
  SIZE_T i = 0;
  SIZE_T last_sep = 0;
  SIZE_T path_len = 0;
  if (!out || out_len == 0) {
    return;
  }
  out[0] = '\0';
  if (!path) {
    return;
  }

  path_len = qapp_strnlen(path, QAPP_MAX_RULE_VALUE * 2);
  for (i = 0; i < path_len; ++i) {
    if (path[i] == '\\' || path[i] == '/') {
      last_sep = i + 1;
    }
  }

  if (last_sep >= path_len) {
    qapp_copy_ascii(out, out_len, path);
    return;
  }

  qapp_copy_ascii(out, out_len, path + last_sep);
}

static VOID qapp_unicode_to_ascii_path(_In_ const UNICODE_STRING* input, _Out_writes_(out_len) CHAR* out, _In_ SIZE_T out_len) {
  SIZE_T i = 0;
  SIZE_T out_idx = 0;
  SIZE_T wchar_count = 0;

  if (!out || out_len == 0) {
    return;
  }
  out[0] = '\0';

  if (!input || !input->Buffer || input->Length == 0) {
    return;
  }

  wchar_count = input->Length / sizeof(WCHAR);
  for (i = 0; i < wchar_count && out_idx + 1 < out_len; ++i) {
    WCHAR wc = input->Buffer[i];
    CHAR c = '?';

    if (wc <= 0x7F) {
      c = (CHAR)wc;
      if (c >= 'A' && c <= 'Z') {
        c = (CHAR)(c - 'A' + 'a');
      } else if (c == '/') {
        c = '\\';
      }
    }

    out[out_idx++] = c;
  }

  out[out_idx] = '\0';
}

static BOOLEAN qapp_is_critical_allowlisted(_In_opt_ const CHAR* image_name) {
  SIZE_T i = 0;
  if (!image_name || image_name[0] == '\0') {
    return FALSE;
  }
  for (i = 0; i < RTL_NUMBER_OF(g_critical_allowlist); ++i) {
    if (qapp_ascii_equals(image_name, g_critical_allowlist[i])) {
      return TRUE;
    }
  }
  return FALSE;
}

static ULONGLONG qapp_hash_fnv1a64(_In_reads_(len) const UCHAR* data, _In_ SIZE_T len) {
  SIZE_T i = 0;
  ULONGLONG hash = 1469598103934665603ULL;
  for (i = 0; i < len; ++i) {
    hash ^= data[i];
    hash *= 1099511628211ULL;
  }
  return hash;
}

static ULONGLONG qapp_build_dedupe_key(
    _In_opt_ const CHAR* rule_id,
    _In_opt_ const CHAR* image_path,
    _In_ ULONG session_id) {
  ULONGLONG hash = 1469598103934665603ULL;
  CHAR session_buf[16];
  const UCHAR separator = (UCHAR)'|';

  if (rule_id) {
    hash ^= qapp_hash_fnv1a64((const UCHAR*)rule_id, qapp_strnlen(rule_id, QAPP_MAX_RULE_ID));
    hash *= 1099511628211ULL;
  }
  hash ^= separator;
  hash *= 1099511628211ULL;
  if (image_path) {
    hash ^= qapp_hash_fnv1a64((const UCHAR*)image_path, qapp_strnlen(image_path, QAPP_MAX_RULE_VALUE));
    hash *= 1099511628211ULL;
  }
  hash ^= separator;
  hash *= 1099511628211ULL;
  (void)RtlStringCchPrintfA(session_buf, sizeof(session_buf), "%u", session_id);
  hash ^= qapp_hash_fnv1a64((const UCHAR*)session_buf, qapp_strnlen(session_buf, sizeof(session_buf)));
  hash *= 1099511628211ULL;
  return hash;
}

static BOOLEAN qapp_should_emit_event_deduped(
    _In_opt_ const CHAR* rule_id,
    _In_opt_ const CHAR* image_path,
    _In_ ULONG session_id,
    _In_ ULONG dedupe_sec) {
  ULONGLONG now_unix = qapp_now_unix_seconds();
  ULONGLONG key_hash = qapp_build_dedupe_key(rule_id, image_path, session_id);
  ULONGLONG expires_at = now_unix + (ULONGLONG)dedupe_sec;
  KIRQL old_irql = PASSIVE_LEVEL;
  LONG free_index = -1;
  LONG i = 0;

  if (dedupe_sec == 0) {
    return TRUE;
  }

  KeAcquireSpinLock(&g_dedupe_lock, &old_irql);
  for (i = 0; i < QAPP_MAX_DEDUPE_SLOTS; ++i) {
    if (g_dedupe_slots[i].expires_at_unix <= now_unix) {
      if (free_index < 0) {
        free_index = i;
      }
      continue;
    }
    if (g_dedupe_slots[i].key_hash == key_hash) {
      KeReleaseSpinLock(&g_dedupe_lock, old_irql);
      return FALSE;
    }
  }

  if (free_index < 0) {
    free_index = 0;
  }

  g_dedupe_slots[free_index].key_hash = key_hash;
  g_dedupe_slots[free_index].expires_at_unix = expires_at;
  KeReleaseSpinLock(&g_dedupe_lock, old_irql);
  return TRUE;
}

static BOOLEAN qapp_rule_is_expired(_In_ const QAPP_RULE* rule, _In_ ULONGLONG now_unix) {
  if (!rule->has_expires_at) {
    return FALSE;
  }
  if (rule->expires_at_unix == 0) {
    return FALSE;
  }
  return now_unix >= rule->expires_at_unix;
}

static BOOLEAN qapp_full_path_matches(_In_ const CHAR* rule_value, _In_ const CHAR* image_path) {
  if (!rule_value || !image_path) {
    return FALSE;
  }
  if (qapp_ascii_equals(rule_value, image_path)) {
    return TRUE;
  }
  if (qapp_ascii_starts_with(image_path, "\\??\\") && qapp_ascii_equals(image_path + 4, rule_value)) {
    return TRUE;
  }
  if (qapp_ascii_starts_with(rule_value, "\\??\\") && qapp_ascii_equals(rule_value + 4, image_path)) {
    return TRUE;
  }
  if (rule_value[0] != '\0' && rule_value[1] == ':' && rule_value[2] == '\\') {
    const CHAR* suffix = rule_value + 2;
    if (qapp_ascii_ends_with(image_path, suffix)) {
      return TRUE;
    }
  }
  return FALSE;
}

static VOID qapp_policy_reset(_Out_ QAPP_POLICY* policy) {
  if (!policy) {
    return;
  }
  RtlZeroMemory(policy, sizeof(*policy));
  policy->configured = FALSE;
  policy->enabled = FALSE;
  (void)RtlStringCchCopyA(policy->mode, sizeof(policy->mode), "blocklist");
  (void)RtlStringCchCopyA(policy->fail_mode, sizeof(policy->fail_mode), "open");
  policy->event_dedupe_sec = 30;
}

static ULONG qapp_parse_u32(_In_opt_ const CHAR* value, _In_ ULONG fallback_value) {
  ULONG out = fallback_value;
  ULONGLONG tmp = 0;
  SIZE_T i = 0;
  if (!value || value[0] == '\0') {
    return fallback_value;
  }
  for (i = 0; value[i] != '\0'; ++i) {
    if (value[i] < '0' || value[i] > '9') {
      return fallback_value;
    }
    tmp = (tmp * 10ULL) + (ULONGLONG)(value[i] - '0');
    if (tmp > 0xFFFFFFFFULL) {
      return fallback_value;
    }
  }
  out = (ULONG)tmp;
  return out;
}

static ULONGLONG qapp_parse_u64(_In_opt_ const CHAR* value, _In_ ULONGLONG fallback_value) {
  ULONGLONG out = fallback_value;
  SIZE_T i = 0;
  if (!value || value[0] == '\0') {
    return fallback_value;
  }
  out = 0;
  for (i = 0; value[i] != '\0'; ++i) {
    if (value[i] < '0' || value[i] > '9') {
      return fallback_value;
    }
    out = (out * 10ULL) + (ULONGLONG)(value[i] - '0');
  }
  return out;
}

static BOOLEAN qapp_parse_rule_key(
    _In_ const CHAR* key,
    _Out_ ULONG* index_out,
    _Out_writes_(field_len) CHAR* field_out,
    _In_ SIZE_T field_len) {
  ULONG idx = 0;
  SIZE_T key_len = qapp_strnlen(key, 128);
  SIZE_T i = 0;
  SIZE_T field_start = 0;
  if (!key || !index_out || !field_out || field_len < 2) {
    return FALSE;
  }
  field_out[0] = '\0';

  if (!qapp_ascii_starts_with(key, "rule.")) {
    return FALSE;
  }

  i = 5;
  if (i >= key_len || key[i] < '0' || key[i] > '9') {
    return FALSE;
  }
  while (i < key_len && key[i] >= '0' && key[i] <= '9') {
    idx = (idx * 10U) + (ULONG)(key[i] - '0');
    if (idx >= QAPP_MAX_RULES) {
      return FALSE;
    }
    i++;
  }
  if (i >= key_len || key[i] != '.') {
    return FALSE;
  }
  field_start = i + 1;
  if (field_start >= key_len) {
    return FALSE;
  }

  (void)RtlStringCchCopyNA(field_out, field_len, key + field_start, field_len - 1);
  field_out[field_len - 1] = '\0';
  *index_out = idx;
  return TRUE;
}

static NTSTATUS qapp_parse_policy_blob(
    _In_reads_or_z_(params_len) const CHAR* params,
    _In_ SIZE_T params_len,
    _Out_ QAPP_POLICY* out_policy,
    _Out_writes_(error_len) CHAR* error_out,
    _In_ SIZE_T error_len) {
  CHAR buffer[QAPP_MAX_PARSE_BUFFER + 1];
  SIZE_T copy_len = 0;
  CHAR* cursor = NULL;

  if (!params || !out_policy) {
    qapp_copy_ascii(error_out, error_len, "invalid_payload");
    return STATUS_INVALID_PARAMETER;
  }

  qapp_policy_reset(out_policy);

  copy_len = params_len;
  if (copy_len == 0) {
    copy_len = qapp_strnlen(params, QAPP_MAX_PARSE_BUFFER);
  }
  if (copy_len == 0 || copy_len > QAPP_MAX_PARSE_BUFFER) {
    qapp_copy_ascii(error_out, error_len, "payload_too_large");
    return STATUS_INVALID_BUFFER_SIZE;
  }

  RtlZeroMemory(buffer, sizeof(buffer));
  RtlCopyMemory(buffer, params, copy_len);
  buffer[copy_len] = '\0';

  cursor = buffer;
  while (*cursor != '\0') {
    CHAR* line_end = cursor;
    CHAR* sep = NULL;
    CHAR key[96];
    CHAR value[QAPP_MAX_RULE_VALUE];
    ULONG rule_idx = 0;
    CHAR rule_field[32];

    while (*line_end != '\0' && *line_end != '\n' && *line_end != '\r') {
      line_end++;
    }
    if (*line_end != '\0') {
      *line_end = '\0';
      line_end++;
      if (*line_end == '\n' || *line_end == '\r') {
        line_end++;
      }
    }

    if (cursor[0] == '\0') {
      cursor = line_end;
      continue;
    }

    sep = cursor;
    while (*sep != '\0' && *sep != '=') {
      sep++;
    }
    if (*sep != '=') {
      cursor = line_end;
      continue;
    }

    *sep = '\0';
    qapp_copy_ascii(key, sizeof(key), cursor);
    qapp_copy_ascii(value, sizeof(value), sep + 1);
    qapp_normalize_ascii_path(key, sizeof(key));

    if (qapp_ascii_equals(key, "enabled")) {
      out_policy->enabled = (value[0] == '1' || qapp_ascii_equals(value, "true"));
      out_policy->configured = TRUE;
    } else if (qapp_ascii_equals(key, "mode")) {
      qapp_normalize_ascii_path(value, sizeof(value));
      qapp_copy_ascii(out_policy->mode, sizeof(out_policy->mode), value);
    } else if (qapp_ascii_equals(key, "fail_mode")) {
      qapp_normalize_ascii_path(value, sizeof(value));
      qapp_copy_ascii(out_policy->fail_mode, sizeof(out_policy->fail_mode), value);
    } else if (qapp_ascii_equals(key, "policy_version")) {
      qapp_copy_ascii(out_policy->policy_version, sizeof(out_policy->policy_version), value);
    } else if (qapp_ascii_equals(key, "policy_hash")) {
      qapp_copy_ascii(out_policy->policy_hash, sizeof(out_policy->policy_hash), value);
    } else if (qapp_ascii_equals(key, "event_dedupe_sec")) {
      out_policy->event_dedupe_sec = qapp_parse_u32(value, 30);
      if (out_policy->event_dedupe_sec > 3600) {
        out_policy->event_dedupe_sec = 3600;
      }
    } else if (qapp_parse_rule_key(key, &rule_idx, rule_field, sizeof(rule_field))) {
      QAPP_RULE* rule = &out_policy->rules[rule_idx];
      rule->used = TRUE;
      if (qapp_ascii_equals(rule_field, "rule_id")) {
        qapp_copy_ascii(rule->rule_id, sizeof(rule->rule_id), value);
      } else if (qapp_ascii_equals(rule_field, "match_type")) {
        qapp_normalize_ascii_path(value, sizeof(value));
        if (qapp_ascii_equals(value, "basename")) {
          rule->match_type = QAPP_MATCH_BASENAME;
        } else if (qapp_ascii_equals(value, "full_path")) {
          rule->match_type = QAPP_MATCH_FULL_PATH;
        } else {
          qapp_copy_ascii(error_out, error_len, "invalid_match_type");
          return STATUS_INVALID_PARAMETER;
        }
      } else if (qapp_ascii_equals(rule_field, "value")) {
        qapp_normalize_ascii_path(value, sizeof(value));
        qapp_copy_ascii(rule->value, sizeof(rule->value), value);
      } else if (qapp_ascii_equals(rule_field, "priority")) {
        rule->priority = qapp_parse_u32(value, 1000);
      } else if (qapp_ascii_equals(rule_field, "expires_at")) {
        ULONGLONG parsed = qapp_parse_u64(value, 0);
        if (parsed > 0) {
          rule->has_expires_at = TRUE;
          rule->expires_at_unix = parsed;
        } else {
          rule->has_expires_at = FALSE;
          rule->expires_at_unix = 0;
        }
      }
    }

    cursor = line_end;
  }

  if (!qapp_ascii_equals(out_policy->mode, "blocklist")) {
    qapp_copy_ascii(error_out, error_len, "invalid_mode");
    return STATUS_INVALID_PARAMETER;
  }
  if (!qapp_ascii_equals(out_policy->fail_mode, "open")) {
    qapp_copy_ascii(error_out, error_len, "invalid_fail_mode");
    return STATUS_INVALID_PARAMETER;
  }

  out_policy->rule_count = 0;
  for (ULONG i = 0; i < QAPP_MAX_RULES; ++i) {
    QAPP_RULE* rule = &out_policy->rules[i];
    if (!rule->used) {
      continue;
    }
    if (rule->priority == 0) {
      rule->priority = 1000;
    }
    if (rule->rule_id[0] == '\0') {
      (void)RtlStringCchPrintfA(rule->rule_id, sizeof(rule->rule_id), "rule-%lu", i);
    }
    if (rule->match_type == QAPP_MATCH_NONE || rule->value[0] == '\0') {
      qapp_copy_ascii(error_out, error_len, "invalid_rule");
      return STATUS_INVALID_PARAMETER;
    }
    if (rule->match_type == QAPP_MATCH_BASENAME) {
      CHAR basename_only[QAPP_MAX_RULE_VALUE];
      qapp_extract_basename(rule->value, basename_only, sizeof(basename_only));
      qapp_copy_ascii(rule->value, sizeof(rule->value), basename_only);
    }
    out_policy->rule_count++;
  }

  if (out_policy->event_dedupe_sec == 0) {
    out_policy->event_dedupe_sec = 30;
  }

  out_policy->configured = TRUE;
  qapp_copy_ascii(error_out, error_len, "");
  return STATUS_SUCCESS;
}

static VOID qapp_process_create_notify(
    _Inout_ PEPROCESS Process,
    _In_ HANDLE ProcessId,
    _Inout_opt_ PPS_CREATE_NOTIFY_INFO CreateInfo) {
  ULONGLONG now_unix = qapp_now_unix_seconds();
  ULONG best_priority = 0xFFFFFFFFUL;
  LONG best_rule_index = -1;
  BOOLEAN matched_full_path = FALSE;
  BOOLEAN should_block = FALSE;
  ULONG dedupe_sec = 30;
  ULONG session_id = 0;
  const BOOLEAN emit_block_events_in_callback = FALSE; // Hotfix: avoid WDF event pipeline calls in process-create callback.
  CHAR image_path[QAPP_MAX_RULE_VALUE];
  CHAR image_name[128];
  CHAR rule_id[QAPP_MAX_RULE_ID];
  CHAR matched_value[QAPP_MAX_RULE_VALUE];
  CHAR match_type[24];
  CHAR reason_code[64];
  CHAR policy_version[QAPP_MAX_POLICY_VERSION];
  CHAR policy_hash[QAPP_MAX_POLICY_HASH];

  UNREFERENCED_PARAMETER(ProcessId);
  UNREFERENCED_PARAMETER(Process);

  if (!CreateInfo || !CreateInfo->ImageFileName) {
    return;
  }

  qapp_unicode_to_ascii_path(CreateInfo->ImageFileName, image_path, sizeof(image_path));
  qapp_extract_basename(image_path, image_name, sizeof(image_name));

  KeEnterCriticalRegion();
  ExAcquirePushLockShared(&g_policy_lock);
  if (!g_policy.configured || !g_policy.enabled) {
    ExReleasePushLockShared(&g_policy_lock);
    KeLeaveCriticalRegion();
    return;
  }

  if (qapp_is_critical_allowlisted(image_name)) {
    ExReleasePushLockShared(&g_policy_lock);
    KeLeaveCriticalRegion();
    return;
  }

  for (ULONG i = 0; i < g_policy.rule_count; ++i) {
    const QAPP_RULE* rule = &g_policy.rules[i];
    if (!rule->used || qapp_rule_is_expired(rule, now_unix)) {
      continue;
    }
    if (rule->match_type != QAPP_MATCH_FULL_PATH) {
      continue;
    }
    if (!qapp_full_path_matches(rule->value, image_path)) {
      continue;
    }
    if (rule->priority < best_priority) {
      best_priority = rule->priority;
      best_rule_index = (LONG)i;
      matched_full_path = TRUE;
    }
  }

  if (best_rule_index < 0) {
    for (ULONG i = 0; i < g_policy.rule_count; ++i) {
      const QAPP_RULE* rule = &g_policy.rules[i];
      if (!rule->used || qapp_rule_is_expired(rule, now_unix)) {
        continue;
      }
      if (rule->match_type != QAPP_MATCH_BASENAME) {
        continue;
      }
      if (!qapp_ascii_equals(rule->value, image_name)) {
        continue;
      }
      if (rule->priority < best_priority) {
        best_priority = rule->priority;
        best_rule_index = (LONG)i;
        matched_full_path = FALSE;
      }
    }
  }

  if (best_rule_index >= 0) {
    const QAPP_RULE* matched_rule = &g_policy.rules[best_rule_index];
    should_block = TRUE;
    dedupe_sec = g_policy.event_dedupe_sec;
    qapp_copy_ascii(rule_id, sizeof(rule_id), matched_rule->rule_id);
    qapp_copy_ascii(matched_value, sizeof(matched_value), matched_rule->value);
    qapp_copy_ascii(match_type, sizeof(match_type), matched_full_path ? "full_path" : "basename");
    qapp_copy_ascii(reason_code, sizeof(reason_code), "blocked_by_policy");
    qapp_copy_ascii(policy_version, sizeof(policy_version), g_policy.policy_version);
    qapp_copy_ascii(policy_hash, sizeof(policy_hash), g_policy.policy_hash);
  }
  ExReleasePushLockShared(&g_policy_lock);
  KeLeaveCriticalRegion();

  if (!should_block) {
    return;
  }

  CreateInfo->CreationStatus = STATUS_ACCESS_DENIED;

  session_id = 0;
  if (emit_block_events_in_callback &&
      qapp_should_emit_event_deduped(rule_id, image_path, session_id, dedupe_sec)) {
    QuoodleEventPipelineEmitAppBlockEvent(
        rule_id,
        match_type,
        matched_value,
        image_path,
        image_name,
        reason_code,
        policy_version,
        policy_hash,
        session_id);
  }
}

NTSTATUS QuoodleAppLockdownInitialize(VOID) {
  NTSTATUS status = STATUS_SUCCESS;
  qapp_policy_reset(&g_policy);
  RtlZeroMemory((PVOID)g_dedupe_slots, sizeof(g_dedupe_slots));
  KeInitializeSpinLock(&g_dedupe_lock);

  status = PsSetCreateProcessNotifyRoutineEx(qapp_process_create_notify, FALSE);
  g_callback_register_status = status;
  if (!NT_SUCCESS(status) && status != STATUS_ACCESS_DENIED && status != STATUS_INVALID_PARAMETER) {
    return status;
  }
  if (NT_SUCCESS(status) || status == STATUS_INVALID_PARAMETER) {
    g_callback_registered = TRUE;
  } else {
    g_callback_registered = FALSE;
  }
  return STATUS_SUCCESS;
}

VOID QuoodleAppLockdownShutdown(VOID) {
  if (g_callback_registered) {
    (VOID)PsSetCreateProcessNotifyRoutineEx(qapp_process_create_notify, TRUE);
    g_callback_registered = FALSE;
  }
  KeEnterCriticalRegion();
  ExAcquirePushLockExclusive(&g_policy_lock);
  qapp_policy_reset(&g_policy);
  InterlockedIncrement(&g_policy_generation);
  ExReleasePushLockExclusive(&g_policy_lock);
  KeLeaveCriticalRegion();
}

NTSTATUS QuoodleAppLockdownReplacePolicy(
    _In_reads_or_z_(params_len) const CHAR* params,
    _In_ SIZE_T params_len,
    _Out_writes_(error_len) CHAR* error_out,
    _In_ SIZE_T error_len) {
  QAPP_POLICY* parsed_policy = NULL;
  NTSTATUS status;

  qapp_copy_ascii(error_out, error_len, "");
  parsed_policy = (QAPP_POLICY*)ExAllocatePool2(POOL_FLAG_NON_PAGED, sizeof(QAPP_POLICY), QAPP_TAG_POLICY);
  if (!parsed_policy) {
    qapp_copy_ascii(error_out, error_len, "out_of_memory");
    return STATUS_INSUFFICIENT_RESOURCES;
  }

  RtlZeroMemory(parsed_policy, sizeof(*parsed_policy));

  status = qapp_parse_policy_blob(params, params_len, parsed_policy, error_out, error_len);
  if (!NT_SUCCESS(status)) {
    ExFreePool(parsed_policy);
    return status;
  }

  KeEnterCriticalRegion();
  ExAcquirePushLockExclusive(&g_policy_lock);
  g_policy = *parsed_policy;
  InterlockedIncrement(&g_policy_generation);
  ExReleasePushLockExclusive(&g_policy_lock);
  KeLeaveCriticalRegion();

  if (parsed_policy->enabled && !g_callback_registered) {
    NTSTATUS register_status = PsSetCreateProcessNotifyRoutineEx(qapp_process_create_notify, FALSE);
    g_callback_register_status = register_status;
    if (NT_SUCCESS(register_status) || register_status == STATUS_INVALID_PARAMETER) {
      g_callback_registered = TRUE;
    }
  }

  ExFreePool(parsed_policy);
  return STATUS_SUCCESS;
}

NTSTATUS QuoodleAppLockdownClearPolicy(
    _Out_writes_(error_len) CHAR* error_out,
    _In_ SIZE_T error_len) {
  qapp_copy_ascii(error_out, error_len, "");
  KeEnterCriticalRegion();
  ExAcquirePushLockExclusive(&g_policy_lock);
  qapp_policy_reset(&g_policy);
  InterlockedIncrement(&g_policy_generation);
  ExReleasePushLockExclusive(&g_policy_lock);
  KeLeaveCriticalRegion();
  return STATUS_SUCCESS;
}

NTSTATUS QuoodleAppLockdownGetStatusJson(
    _Out_writes_(json_len) CHAR* json_out,
    _In_ SIZE_T json_len,
    _Out_writes_(error_len) CHAR* error_out,
    _In_ SIZE_T error_len) {
  NTSTATUS status = STATUS_SUCCESS;
  LONG generation = 0;

  if (!json_out || json_len < 16) {
    qapp_copy_ascii(error_out, error_len, "buffer_too_small");
    return STATUS_BUFFER_TOO_SMALL;
  }

  KeEnterCriticalRegion();
  ExAcquirePushLockShared(&g_policy_lock);
  generation = InterlockedCompareExchange(&g_policy_generation, 0, 0);
  status = RtlStringCchPrintfA(
      json_out,
      json_len,
      "{\"status\":\"ok\",\"configured\":%s,\"enabled\":%s,"
      "\"mode\":\"%s\",\"fail_mode\":\"%s\",\"policy_version\":\"%s\","
      "\"policy_hash\":\"%s\",\"rule_count\":%lu,\"event_dedupe_sec\":%lu,"
      "\"generation\":%ld,\"callback_registered\":%s,"
      "\"callback_register_status\":%ld,\"callback_register_status_hex\":\"0x%08lx\"}",
      g_policy.configured ? "true" : "false",
      g_policy.enabled ? "true" : "false",
      g_policy.mode,
      g_policy.fail_mode,
      g_policy.policy_version,
      g_policy.policy_hash,
      g_policy.rule_count,
      g_policy.event_dedupe_sec,
      generation,
      g_callback_registered ? "true" : "false",
      g_callback_register_status,
      (ULONG)g_callback_register_status);
  ExReleasePushLockShared(&g_policy_lock);
  KeLeaveCriticalRegion();

  if (!NT_SUCCESS(status)) {
    qapp_copy_ascii(error_out, error_len, "status_serialize_failed");
    return STATUS_BUFFER_OVERFLOW;
  }

  qapp_copy_ascii(error_out, error_len, "");
  return STATUS_SUCCESS;
}
