#include <ntddk.h>
#include <wdf.h>
#include <ntstrsafe.h>

#include "../quoodle_ioctl.h"

#define QUOODLE_TAG 'Qood'
#define QUOODLE_MAX_CANONICAL 2048
#define QUOODLE_HMAC_KEY_MAX 128

static volatile LONGLONG g_last_seq = 0;
static LONG g_exec_counter = 0;
static volatile LONGLONG g_event_counter = 0;
static volatile LONGLONG g_event_dropped = 0;
static volatile LONGLONG g_validation_rejects = 0;
static volatile LONGLONG g_runtime_internal_errors = 0;

#define QUOODLE_EVENT_RING_SIZE 16
static QUOODLE_KERNEL_EVENT g_event_ring[QUOODLE_EVENT_RING_SIZE];
static ULONG g_event_head = 0;
static ULONG g_event_tail = 0;
static ULONG g_event_count = 0;
static WDFSPINLOCK g_event_lock = NULL;
static WDFQUEUE g_wait_queue = NULL;

static UCHAR g_hmac_key[QUOODLE_HMAC_KEY_MAX];
static ULONG g_hmac_key_len = 0;
static BOOLEAN g_hmac_ready = FALSE;

typedef enum _QUOODLE_SHUTDOWN_ACTION {
  QuoodleShutdownNoReboot = 0,
  QuoodleShutdownReboot = 1,
  QuoodleShutdownPowerOff = 2
} QUOODLE_SHUTDOWN_ACTION;

NTSYSAPI NTSTATUS NTAPI NtShutdownSystem(_In_ QUOODLE_SHUTDOWN_ACTION Action);

static size_t q_strnlen_a(const CHAR* s, size_t max_len) {
  size_t len = 0;
  if (!s) {
    return 0;
  }
  while (len < max_len && s[len] != '\0') {
    len++;
  }
  return len;
}

// ----------------- Crypto helpers (SHA256 + HMAC) -----------------
typedef struct _QSHA256_CTX {
  UINT32 state[8];
  UINT64 bitlen;
  UINT32 datalen;
  UCHAR data[64];
} QSHA256_CTX;

static const UINT32 qsha_k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

static __forceinline UINT32 qrotr(UINT32 x, UINT32 n) { return (x >> n) | (x << (32 - n)); }

static void qsha256_transform(QSHA256_CTX* ctx, const UCHAR data[64]) {
  UINT32 a, b, c, d, e, f, g, h, i, j, t1, t2, m[64];

  for (i = 0, j = 0; i < 16; ++i, j += 4) {
    m[i] = ((UINT32)data[j] << 24) | ((UINT32)data[j + 1] << 16) | ((UINT32)data[j + 2] << 8) | ((UINT32)data[j + 3]);
  }
  for (; i < 64; ++i) {
    UINT32 s0 = qrotr(m[i - 15], 7) ^ qrotr(m[i - 15], 18) ^ (m[i - 15] >> 3);
    UINT32 s1 = qrotr(m[i - 2], 17) ^ qrotr(m[i - 2], 19) ^ (m[i - 2] >> 10);
    m[i] = m[i - 16] + s0 + m[i - 7] + s1;
  }

  a = ctx->state[0]; b = ctx->state[1]; c = ctx->state[2]; d = ctx->state[3];
  e = ctx->state[4]; f = ctx->state[5]; g = ctx->state[6]; h = ctx->state[7];

  for (i = 0; i < 64; ++i) {
    UINT32 S1 = qrotr(e, 6) ^ qrotr(e, 11) ^ qrotr(e, 25);
    UINT32 ch = (e & f) ^ ((~e) & g);
    t1 = h + S1 + ch + qsha_k[i] + m[i];
    UINT32 S0 = qrotr(a, 2) ^ qrotr(a, 13) ^ qrotr(a, 22);
    UINT32 maj = (a & b) ^ (a & c) ^ (b & c);
    t2 = S0 + maj;

    h = g; g = f; f = e; e = d + t1;
    d = c; c = b; b = a; a = t1 + t2;
  }

  ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
  ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

static void qsha256_init(QSHA256_CTX* ctx) {
  ctx->datalen = 0;
  ctx->bitlen = 0;
  ctx->state[0] = 0x6a09e667;
  ctx->state[1] = 0xbb67ae85;
  ctx->state[2] = 0x3c6ef372;
  ctx->state[3] = 0xa54ff53a;
  ctx->state[4] = 0x510e527f;
  ctx->state[5] = 0x9b05688c;
  ctx->state[6] = 0x1f83d9ab;
  ctx->state[7] = 0x5be0cd19;
}

static void qsha256_update(QSHA256_CTX* ctx, const UCHAR* data, size_t len) {
  size_t i;
  for (i = 0; i < len; ++i) {
    ctx->data[ctx->datalen] = data[i];
    ctx->datalen++;
    if (ctx->datalen == 64) {
      qsha256_transform(ctx, ctx->data);
      ctx->bitlen += 512;
      ctx->datalen = 0;
    }
  }
}

static void qsha256_final(QSHA256_CTX* ctx, UCHAR out[32]) {
  UINT32 i = ctx->datalen;

  if (ctx->datalen < 56) {
    ctx->data[i++] = 0x80;
    while (i < 56) ctx->data[i++] = 0x00;
  } else {
    ctx->data[i++] = 0x80;
    while (i < 64) ctx->data[i++] = 0x00;
    qsha256_transform(ctx, ctx->data);
    RtlZeroMemory(ctx->data, 56);
  }

  ctx->bitlen += ((UINT64)ctx->datalen) * 8ULL;
  ctx->data[63] = (UCHAR)(ctx->bitlen);
  ctx->data[62] = (UCHAR)(ctx->bitlen >> 8);
  ctx->data[61] = (UCHAR)(ctx->bitlen >> 16);
  ctx->data[60] = (UCHAR)(ctx->bitlen >> 24);
  ctx->data[59] = (UCHAR)(ctx->bitlen >> 32);
  ctx->data[58] = (UCHAR)(ctx->bitlen >> 40);
  ctx->data[57] = (UCHAR)(ctx->bitlen >> 48);
  ctx->data[56] = (UCHAR)(ctx->bitlen >> 56);
  qsha256_transform(ctx, ctx->data);

  for (i = 0; i < 4; ++i) {
    out[i] = (UCHAR)((ctx->state[0] >> (24 - i * 8)) & 0xFF);
    out[i + 4] = (UCHAR)((ctx->state[1] >> (24 - i * 8)) & 0xFF);
    out[i + 8] = (UCHAR)((ctx->state[2] >> (24 - i * 8)) & 0xFF);
    out[i + 12] = (UCHAR)((ctx->state[3] >> (24 - i * 8)) & 0xFF);
    out[i + 16] = (UCHAR)((ctx->state[4] >> (24 - i * 8)) & 0xFF);
    out[i + 20] = (UCHAR)((ctx->state[5] >> (24 - i * 8)) & 0xFF);
    out[i + 24] = (UCHAR)((ctx->state[6] >> (24 - i * 8)) & 0xFF);
    out[i + 28] = (UCHAR)((ctx->state[7] >> (24 - i * 8)) & 0xFF);
  }
}

static void qhmac_sha256(const UCHAR* key, size_t key_len, const UCHAR* msg, size_t msg_len, UCHAR out[32]) {
  UCHAR k_ipad[64];
  UCHAR k_opad[64];
  UCHAR tk[32];
  size_t i;

  if (key_len > 64) {
    QSHA256_CTX tctx;
    qsha256_init(&tctx);
    qsha256_update(&tctx, key, key_len);
    qsha256_final(&tctx, tk);
    key = tk;
    key_len = 32;
  }

  RtlFillMemory(k_ipad, sizeof(k_ipad), 0x36);
  RtlFillMemory(k_opad, sizeof(k_opad), 0x5c);
  for (i = 0; i < key_len; ++i) {
    k_ipad[i] ^= key[i];
    k_opad[i] ^= key[i];
  }

  QSHA256_CTX ctx;
  UCHAR inner[32];
  qsha256_init(&ctx);
  qsha256_update(&ctx, k_ipad, sizeof(k_ipad));
  qsha256_update(&ctx, msg, msg_len);
  qsha256_final(&ctx, inner);

  qsha256_init(&ctx);
  qsha256_update(&ctx, k_opad, sizeof(k_opad));
  qsha256_update(&ctx, inner, sizeof(inner));
  qsha256_final(&ctx, out);

  RtlSecureZeroMemory(tk, sizeof(tk));
  RtlSecureZeroMemory(inner, sizeof(inner));
  RtlSecureZeroMemory(k_ipad, sizeof(k_ipad));
  RtlSecureZeroMemory(k_opad, sizeof(k_opad));
}

// ----------------- Base64 helpers -----------------
static const CHAR q_b64_tbl[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static INT q_b64_index(CHAR c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}

static BOOLEAN q_base64_decode(const CHAR* in, ULONG in_len, UCHAR* out, ULONG out_cap, ULONG* out_len) {
  ULONG i = 0, j = 0;
  UINT32 val = 0;
  INT valb = -8;
  while (i < in_len) {
    CHAR c = in[i++];
    if (c == '=') break;
    INT d = q_b64_index(c);
    if (d < 0) return FALSE;
    val = (val << 6) | (UINT32)d;
    valb += 6;
    if (valb >= 0) {
      if (j >= out_cap) return FALSE;
      out[j++] = (UCHAR)((val >> valb) & 0xFF);
      valb -= 8;
    }
  }
  *out_len = j;
  return TRUE;
}

static BOOLEAN q_base64_encode(const UCHAR* in, ULONG in_len, CHAR* out, ULONG out_cap, ULONG* out_len) {
  ULONG i;
  ULONG olen = 4 * ((in_len + 2) / 3);
  if (out_cap < olen + 1) return FALSE;

  for (i = 0; i < in_len; i += 3) {
    UINT32 v = ((UINT32)in[i]) << 16;
    if (i + 1 < in_len) v |= ((UINT32)in[i + 1]) << 8;
    if (i + 2 < in_len) v |= ((UINT32)in[i + 2]);

    out[(i / 3) * 4 + 0] = q_b64_tbl[(v >> 18) & 0x3F];
    out[(i / 3) * 4 + 1] = q_b64_tbl[(v >> 12) & 0x3F];
    out[(i / 3) * 4 + 2] = (i + 1 < in_len) ? q_b64_tbl[(v >> 6) & 0x3F] : '=';
    out[(i / 3) * 4 + 3] = (i + 2 < in_len) ? q_b64_tbl[v & 0x3F] : '=';
  }

  out[olen] = '\0';
  *out_len = olen;
  return TRUE;
}

static BOOLEAN q_const_time_eq(const UCHAR* a, const UCHAR* b, ULONG len) {
  UCHAR diff = 0;
  ULONG i;
  for (i = 0; i < len; ++i) diff |= (a[i] ^ b[i]);
  return diff == 0;
}

static VOID DeleteUserSymbolicLinks(VOID) {
  UNICODE_STRING primarySymLink;
  UNICODE_STRING legacySymLink;
  RtlInitUnicodeString(&primarySymLink, QUOODLE_DOS_DEVICE_NAME);
  RtlInitUnicodeString(&legacySymLink, QUOODLE_DOS_DEVICE_NAME_LEGACY);
  (VOID)IoDeleteSymbolicLink(&primarySymLink);
  (VOID)IoDeleteSymbolicLink(&legacySymLink);
}

static NTSTATUS CreateUserSymbolicLinks(VOID) {
  UNICODE_STRING deviceName;
  UNICODE_STRING primarySymLink;
  UNICODE_STRING legacySymLink;
  NTSTATUS status;

  RtlInitUnicodeString(&deviceName, QUOODLE_DEVICE_NAME);
  RtlInitUnicodeString(&primarySymLink, QUOODLE_DOS_DEVICE_NAME);
  RtlInitUnicodeString(&legacySymLink, QUOODLE_DOS_DEVICE_NAME_LEGACY);

  DeleteUserSymbolicLinks();

  status = IoCreateSymbolicLink(&primarySymLink, &deviceName);
  if (!NT_SUCCESS(status) && status != STATUS_OBJECT_NAME_COLLISION) {
    return status;
  }

  status = IoCreateSymbolicLink(&legacySymLink, &deviceName);
  if (!NT_SUCCESS(status) && status != STATUS_OBJECT_NAME_COLLISION) {
    (VOID)IoDeleteSymbolicLink(&primarySymLink);
    return status;
  }

  return STATUS_SUCCESS;
}

// ----------------- Transport helpers -----------------
static uint64_t UnixTimestampSeconds(void) {
  LARGE_INTEGER systemTime;
  KeQuerySystemTime(&systemTime);
  const LONGLONG EPOCH_DELTA = 116444736000000000LL;
  if (systemTime.QuadPart < EPOCH_DELTA) {
    return 0;
  }
  return (uint64_t)((systemTime.QuadPart - EPOCH_DELTA) / 10000000ULL);
}

static BOOLEAN IsNullTerminatedA(const CHAR* s, SIZE_T cap) {
  SIZE_T i;
  if (!s || cap == 0) return FALSE;
  for (i = 0; i < cap; ++i) {
    if (s[i] == '\0') return TRUE;
  }
  return FALSE;
}

static SIZE_T BoundedStrLenA(const CHAR* s, SIZE_T cap) {
  SIZE_T i = 0;
  if (!s) return 0;
  while (i < cap && s[i] != '\0') {
    ++i;
  }
  return i;
}

static BOOLEAN ValidateRequestPayload(const QUOODLE_IOCTL_REQUEST* req) {
  if (!req) return FALSE;
  if (!IsNullTerminatedA(req->request_id, sizeof(req->request_id))) return FALSE;
  if (!IsNullTerminatedA(req->policy_hash, sizeof(req->policy_hash))) return FALSE;
  if (!IsNullTerminatedA(req->command_message_id, sizeof(req->command_message_id))) return FALSE;
  if (!IsNullTerminatedA(req->signature_b64, sizeof(req->signature_b64))) return FALSE;

  if (req->params_length >= QUOODLE_MAX_PARAMS) return FALSE;
  if (!IsNullTerminatedA(req->params_json, sizeof(req->params_json))) return FALSE;
  if (req->params_json[req->params_length] != '\0') return FALSE;

  return TRUE;
}

static BOOLEAN IsTimestampFresh(uint64_t ts) {
  uint64_t now = UnixTimestampSeconds();
  if (ts > now) {
    return (ts - now) <= QUOODLE_ALLOWED_TIMESTAMP_SKEW_SEC;
  }
  return (now - ts) <= QUOODLE_ALLOWED_TIMESTAMP_SKEW_SEC;
}

static NTSTATUS BuildCanonicalRequest(const QUOODLE_IOCTL_REQUEST* req, CHAR* out, SIZE_T out_cap, SIZE_T* out_len) {
  NTSTATUS st;
  SIZE_T req_id_len = BoundedStrLenA(req->request_id, sizeof(req->request_id));
  SIZE_T cmd_len = BoundedStrLenA(req->command_message_id, sizeof(req->command_message_id));
  SIZE_T policy_len = BoundedStrLenA(req->policy_hash, sizeof(req->policy_hash));

  st = RtlStringCchPrintfA(
      out,
      out_cap,
      "v1\nseq=%I64u\ncmd=%u:%.*s\nop=%u\nparams=%u:%.*s\npolicy=%u:%.*s\nreq=%u:%.*s\nts=%I64u\n",
      req->agent_sequence,
      (UINT32)cmd_len, (INT)cmd_len, req->command_message_id,
      req->opcode,
      req->params_length, (INT)req->params_length, req->params_json,
      (UINT32)policy_len, (INT)policy_len, req->policy_hash,
      (UINT32)req_id_len, (INT)req_id_len, req->request_id,
      req->timestamp_unix);
  if (!NT_SUCCESS(st)) return STATUS_BUFFER_TOO_SMALL;

  *out_len = BoundedStrLenA(out, out_cap);
  return STATUS_SUCCESS;
}

static NTSTATUS BuildCanonicalResponse(const QUOODLE_IOCTL_RESPONSE* resp, CHAR* out, SIZE_T out_cap, SIZE_T* out_len) {
  NTSTATUS st;
  SIZE_T req_id_len = BoundedStrLenA(resp->request_id, sizeof(resp->request_id));
  SIZE_T kexec_len = BoundedStrLenA(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
  SIZE_T err_len = BoundedStrLenA(resp->error_message, sizeof(resp->error_message));

  st = RtlStringCchPrintfA(
      out,
      out_cap,
      "v1\nstatus=%u\nerror=%u\nkexec=%u:%.*s\nreq=%u:%.*s\nresult=%u:%.*s\nmsg=%u:%.*s\nts=%I64u\n",
      resp->status,
      resp->error_code,
      (UINT32)kexec_len, (INT)kexec_len, resp->kernel_exec_id,
      (UINT32)req_id_len, (INT)req_id_len, resp->request_id,
      resp->result_length, (INT)resp->result_length, resp->result_json,
      (UINT32)err_len, (INT)err_len, resp->error_message,
      resp->timestamp_unix);
  if (!NT_SUCCESS(st)) return STATUS_BUFFER_TOO_SMALL;

  *out_len = BoundedStrLenA(out, out_cap);
  return STATUS_SUCCESS;
}

static BOOLEAN VerifyRequestSignature(const QUOODLE_IOCTL_REQUEST* req) {
  UCHAR provided[64];
  ULONG provided_len = 0;
  UCHAR expected[QUOODLE_HMAC_SHA256_BYTES];
  CHAR canonical[QUOODLE_MAX_CANONICAL];
  SIZE_T canonical_len = 0;

  if (!g_hmac_ready || g_hmac_key_len == 0) {
    return FALSE;
  }

  if (!q_base64_decode(req->signature_b64, req->signature_length, provided, sizeof(provided), &provided_len)) {
    return FALSE;
  }
  if (provided_len != QUOODLE_HMAC_SHA256_BYTES) {
    return FALSE;
  }

  if (!NT_SUCCESS(BuildCanonicalRequest(req, canonical, sizeof(canonical), &canonical_len))) {
    return FALSE;
  }

  qhmac_sha256(g_hmac_key, g_hmac_key_len, (const UCHAR*)canonical, canonical_len, expected);
  return q_const_time_eq(provided, expected, QUOODLE_HMAC_SHA256_BYTES);
}

static VOID SignResponse(QUOODLE_IOCTL_RESPONSE* resp) {
  UCHAR digest[QUOODLE_HMAC_SHA256_BYTES];
  CHAR canonical[QUOODLE_MAX_CANONICAL];
  SIZE_T canonical_len = 0;
  ULONG sig_len = 0;

  resp->signature_length = 0;
  resp->signature_b64[0] = '\0';

  if (!g_hmac_ready || g_hmac_key_len == 0) {
    return;
  }

  if (!NT_SUCCESS(BuildCanonicalResponse(resp, canonical, sizeof(canonical), &canonical_len))) {
    return;
  }

  qhmac_sha256(g_hmac_key, g_hmac_key_len, (const UCHAR*)canonical, canonical_len, digest);
  if (q_base64_encode(digest, sizeof(digest), resp->signature_b64, sizeof(resp->signature_b64), &sig_len)) {
    resp->signature_length = sig_len;
  }
  RtlSecureZeroMemory(digest, sizeof(digest));
}

static NTSTATUS LoadHmacKeyFromRegistry(_In_ PUNICODE_STRING RegistryPath) {
  WCHAR paramsPathBuf[512];
  UNICODE_STRING paramsPath;
  HANDLE key = NULL;
  OBJECT_ATTRIBUTES oa;
  UNICODE_STRING valueName;
  NTSTATUS status;
  ULONG needed = 0;
  PKEY_VALUE_PARTIAL_INFORMATION kvpi = NULL;

  if (!RegistryPath || !RegistryPath->Buffer) {
    return STATUS_INVALID_PARAMETER;
  }

  status = RtlStringCchPrintfW(paramsPathBuf, RTL_NUMBER_OF(paramsPathBuf), L"%wZ\\Parameters", RegistryPath);
  if (!NT_SUCCESS(status)) {
    return STATUS_BUFFER_TOO_SMALL;
  }

  RtlInitUnicodeString(&paramsPath, paramsPathBuf);
  InitializeObjectAttributes(&oa, &paramsPath, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);

  status = ZwOpenKey(&key, KEY_READ, &oa);
  if (!NT_SUCCESS(status)) {
    return status;
  }

  RtlInitUnicodeString(&valueName, L"HmacKey");
  status = ZwQueryValueKey(key, &valueName, KeyValuePartialInformation, NULL, 0, &needed);
  if (status != STATUS_BUFFER_TOO_SMALL && status != STATUS_BUFFER_OVERFLOW) {
    ZwClose(key);
    return status;
  }

  kvpi = (PKEY_VALUE_PARTIAL_INFORMATION)ExAllocatePool2(POOL_FLAG_NON_PAGED, needed, QUOODLE_TAG);
  if (!kvpi) {
    ZwClose(key);
    return STATUS_INSUFFICIENT_RESOURCES;
  }

  status = ZwQueryValueKey(key, &valueName, KeyValuePartialInformation, kvpi, needed, &needed);
  if (NT_SUCCESS(status) && (kvpi->Type == REG_SZ || kvpi->Type == REG_EXPAND_SZ) && kvpi->DataLength >= sizeof(WCHAR)) {
    UNICODE_STRING us;
    ANSI_STRING as;
    us.Buffer = (PWCH)kvpi->Data;
    us.Length = (USHORT)(kvpi->DataLength - sizeof(WCHAR));
    us.MaximumLength = (USHORT)kvpi->DataLength;

    status = RtlUnicodeStringToAnsiString(&as, &us, TRUE);
    if (NT_SUCCESS(status)) {
      SIZE_T copy_len = (as.Length < QUOODLE_HMAC_KEY_MAX) ? as.Length : QUOODLE_HMAC_KEY_MAX;
      RtlCopyMemory(g_hmac_key, as.Buffer, copy_len);
      g_hmac_key_len = (ULONG)copy_len;
      g_hmac_ready = (copy_len > 0) ? TRUE : FALSE;
      RtlFreeAnsiString(&as);
    }
  }

  if (kvpi) {
    ExFreePool(kvpi);
  }
  ZwClose(key);
  return status;
}

// ----------------- Existing behavior helpers -----------------
static void BuildExecId(char* buffer, size_t buffer_len) {
  LONG id = InterlockedIncrement(&g_exec_counter);
  (void)RtlStringCchPrintfA(buffer, buffer_len, "kexec-%ld", id);
}

static void InitKernelEvent(QUOODLE_KERNEL_EVENT* evt, uint32_t type, const char* payload_json) {
  RtlZeroMemory(evt, sizeof(*evt));
  evt->event_id = (uint64_t)InterlockedIncrement64(&g_event_counter);
  evt->event_type = type;
  evt->timestamp_unix = UnixTimestampSeconds();
  if (payload_json && *payload_json) {
    size_t max_len = sizeof(evt->payload_json) - 1;
    size_t len = q_strnlen_a(payload_json, max_len);
    if (len > max_len) {
      len = max_len;
    }
    RtlCopyMemory(evt->payload_json, payload_json, len);
    evt->payload_json[len] = '\0';
    evt->payload_length = (uint32_t)len;
  }
}

static BOOLEAN PopKernelEvent(QUOODLE_KERNEL_EVENT* out) {
  BOOLEAN has_event = FALSE;
  if (!g_event_lock) {
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

static void PushKernelEvent(const QUOODLE_KERNEL_EVENT* evt) {
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

static void DeliverOrQueueKernelEvent(const QUOODLE_KERNEL_EVENT* evt) {
  if (g_wait_queue) {
    WDFREQUEST wait_request = NULL;
    NTSTATUS status = WdfIoQueueRetrieveNextRequest(g_wait_queue, &wait_request);
    if (NT_SUCCESS(status) && wait_request) {
      QUOODLE_KERNEL_EVENT* out = NULL;
      size_t out_len = 0;
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
  PushKernelEvent(evt);
}

static const char* OpcodeToString(QUOODLE_OPCODE opcode) {
  switch (opcode) {
    case QOP_EXEC_LOCK_SCREEN: return "LOCK_SCREEN";
    case QOP_EXEC_REBOOT: return "REBOOT";
    case QOP_EXEC_SHUTDOWN: return "SHUTDOWN";
    case QOP_EXEC_LOGOUT: return "LOGOUT";
    case QOP_EXEC_PING: return "PING";
    case QOP_EXEC_COLLECT_SYSTEM_INFO: return "COLLECT_SYSTEM_INFO";
    case QOP_EXEC_GET_PROCESS_LIST: return "GET_PROCESS_LIST";
    case QOP_EXEC_VALIDATE_UPDATE_PACKAGE: return "VALIDATE_UPDATE_PACKAGE";
    case QOP_STAGE_UPDATE: return "STAGE_UPDATE";
    case QOP_COMMIT_UPDATE: return "COMMIT_UPDATE";
    case QOP_ROLLBACK_UPDATE: return "ROLLBACK_UPDATE";
    case QOP_EXEC_RUN_ATTESTATION: return "RUN_ATTESTATION";
    case QOP_EXEC_RUN_TAMPER_CHECK: return "RUN_TAMPER_CHECK";
    case QOP_EXEC_SELF_REPAIR: return "SELF_REPAIR";
    default: return "UNKNOWN";
  }
}

static const char* OpcodeCategory(QUOODLE_OPCODE opcode) {
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

static const char* OpcodeSubtype(QUOODLE_OPCODE opcode) {
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

static QUOODLE_KERNEL_EVENT_TYPE EventTypeForOpcode(QUOODLE_OPCODE opcode) {
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

static ULONG CurrentQueueDepth(VOID) {
  ULONG depth = 0;
  if (!g_event_lock) {
    return 0;
  }
  WdfSpinLockAcquire(g_event_lock);
  depth = g_event_count;
  WdfSpinLockRelease(g_event_lock);
  return depth;
}

static void EmitKernelCategoryEvent(
    QUOODLE_KERNEL_EVENT_TYPE event_type,
    const char* category,
    const char* subtype,
    const char* severity,
    const char* decision,
    const char* reason_code,
    const char* opcode,
    ULONG error_code,
    ULONGLONG duration_ms,
    const char* policy_ref) {
  CHAR payload[QUOODLE_MAX_EVENT_PAYLOAD];
  ULONGLONG dropped = (ULONGLONG)InterlockedCompareExchange64(&g_event_dropped, 0, 0);
  ULONGLONG validation_rejects = (ULONGLONG)InterlockedCompareExchange64(&g_validation_rejects, 0, 0);
  ULONGLONG runtime_internal_errors = (ULONGLONG)InterlockedCompareExchange64(&g_runtime_internal_errors, 0, 0);
  ULONG queue_depth = CurrentQueueDepth();

  if (!category) category = "runtime";
  if (!subtype) subtype = "event";
  if (!severity) severity = "info";
  if (!decision) decision = "observe";
  if (!reason_code) reason_code = "none";
  if (!opcode) opcode = "UNKNOWN";
  if (!policy_ref) policy_ref = "";

  (void)RtlStringCchPrintfA(payload, sizeof(payload),
                            "{\"category\":\"%s\",\"subtype\":\"%s\",\"severity\":\"%s\",\"decision\":\"%s\","
                            "\"reason_code\":\"%s\",\"opcode\":\"%s\",\"error_code\":%u,\"duration_ms\":%I64u,"
                            "\"queue_depth\":%u,\"drop_count\":%I64u,\"validation_reject_count\":%I64u,"
                            "\"runtime_error_count\":%I64u,\"policy_ref\":\"%s\",\"masked_fields\":[]}",
                            category, subtype, severity, decision, reason_code,
                            opcode, error_code, duration_ms, queue_depth, dropped,
                            validation_rejects, runtime_internal_errors, policy_ref);
  QUOODLE_KERNEL_EVENT evt;
  InitKernelEvent(&evt, event_type, payload);
  DeliverOrQueueKernelEvent(&evt);
}

static void EmitOpcodeEvent(
    QUOODLE_OPCODE opcode,
    const QUOODLE_IOCTL_RESPONSE* resp,
    ULONGLONG duration_ms,
    const char* policy_ref) {
  const char* status = resp->status == 0 ? "ok" : "error";
  const char* opcode_str = OpcodeToString(opcode);
  const char* category = OpcodeCategory(opcode);
  const char* subtype = OpcodeSubtype(opcode);
  const char* severity = resp->status == 0 ? "info" : "high";
  const char* decision = resp->status == 0 ? "allow" : "deny";
  EmitKernelCategoryEvent(
      EventTypeForOpcode(opcode),
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

static void EmitValidationRejectEvent(
    QUOODLE_OPCODE opcode,
    const QUOODLE_IOCTL_RESPONSE* resp,
    const char* reason_code,
    ULONGLONG duration_ms,
    const char* policy_ref) {
  const char* opcode_str = OpcodeToString(opcode);
  EmitKernelCategoryEvent(
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

static void InitResponse(QUOODLE_IOCTL_RESPONSE* resp, const char* request_id) {
  RtlZeroMemory(resp, sizeof(*resp));
  resp->version = QUOODLE_IOCTL_VERSION;
  resp->timestamp_unix = UnixTimestampSeconds();
  resp->status = 1;
  resp->error_code = 9000;
  if (request_id && *request_id) {
    RtlStringCchCopyA(resp->request_id, sizeof(resp->request_id), request_id);
  }
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "not_implemented");
  resp->result_length = 0;
  resp->signature_length = 0;
  resp->signature_b64[0] = '\0';
}

static BOOLEAN UpdateSequenceIfNew(uint64_t seq) {
  LONGLONG current = InterlockedCompareExchange64(&g_last_seq, 0, 0);
  if ((LONGLONG)seq <= current) {
    return FALSE;
  }
  while (InterlockedCompareExchange64(&g_last_seq, (LONGLONG)seq, current) != current) {
    current = InterlockedCompareExchange64(&g_last_seq, 0, 0);
    if ((LONGLONG)seq <= current) {
      return FALSE;
    }
  }
  return TRUE;
}

static void HandlePing(QUOODLE_IOCTL_RESPONSE* resp) {
  resp->status = 0;
  resp->error_code = 0;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "");
  BuildExecId(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
  RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"ok\",\"message\":\"pong\"}");
  resp->result_length = (uint32_t)q_strnlen_a(resp->result_json, sizeof(resp->result_json));
}

static void HandleReboot(QUOODLE_IOCTL_RESPONSE* resp) {
  NTSTATUS status = NtShutdownSystem(QuoodleShutdownReboot);
  if (NT_SUCCESS(status)) {
    resp->status = 0;
    resp->error_code = 0;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "");
    BuildExecId(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
    RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"ok\",\"message\":\"reboot_initiated\"}");
    resp->result_length = (uint32_t)q_strnlen_a(resp->result_json, sizeof(resp->result_json));
  } else {
    resp->status = 1;
    resp->error_code = 5002;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "reboot_failed");
  }
}

static void HandleShutdown(QUOODLE_IOCTL_RESPONSE* resp) {
  NTSTATUS status = NtShutdownSystem(QuoodleShutdownPowerOff);
  if (NT_SUCCESS(status)) {
    resp->status = 0;
    resp->error_code = 0;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "");
    BuildExecId(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
    RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"ok\",\"message\":\"shutdown_initiated\"}");
    resp->result_length = (uint32_t)q_strnlen_a(resp->result_json, sizeof(resp->result_json));
  } else {
    resp->status = 1;
    resp->error_code = 5003;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "shutdown_failed");
  }
}

static void HandleNotSupported(QUOODLE_IOCTL_RESPONSE* resp) {
  resp->status = 1;
  resp->error_code = QERR_NOT_SUPPORTED;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "not_supported");
  RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"not_supported\"}");
  resp->result_length = (uint32_t)q_strnlen_a(resp->result_json, sizeof(resp->result_json));
}

static VOID QuoodleEvtIoDeviceControl(_In_ WDFQUEUE Queue,
                                      _In_ WDFREQUEST Request,
                                      _In_ size_t OutputBufferLength,
                                      _In_ size_t InputBufferLength,
                                      _In_ ULONG IoControlCode) {
  UNREFERENCED_PARAMETER(Queue);

  if (IoControlCode == IOCTL_QUOODLE_WAIT_EVENT) {
    if (OutputBufferLength < sizeof(QUOODLE_KERNEL_EVENT)) {
      WdfRequestComplete(Request, STATUS_BUFFER_TOO_SMALL);
      return;
    }

    QUOODLE_KERNEL_EVENT* out = NULL;
    size_t out_len = 0;
    NTSTATUS status = WdfRequestRetrieveOutputBuffer(Request, sizeof(QUOODLE_KERNEL_EVENT), (PVOID*)&out, &out_len);
    if (!NT_SUCCESS(status) || out == NULL) {
      WdfRequestComplete(Request, STATUS_INVALID_PARAMETER);
      return;
    }

    QUOODLE_KERNEL_EVENT evt;
    if (PopKernelEvent(&evt)) {
      RtlCopyMemory(out, &evt, sizeof(evt));
      WdfRequestCompleteWithInformation(Request, STATUS_SUCCESS, sizeof(QUOODLE_KERNEL_EVENT));
      return;
    }

    status = WdfRequestForwardToIoQueue(Request, g_wait_queue);
    if (!NT_SUCCESS(status)) {
      WdfRequestComplete(Request, status);
    }
    return;
  }

  if (IoControlCode != IOCTL_QUOODLE_EXECUTE) {
    WdfRequestComplete(Request, STATUS_INVALID_DEVICE_REQUEST);
    return;
  }

  if (InputBufferLength < sizeof(QUOODLE_IOCTL_REQUEST) || OutputBufferLength < sizeof(QUOODLE_IOCTL_RESPONSE)) {
    WdfRequestComplete(Request, STATUS_BUFFER_TOO_SMALL);
    return;
  }

  QUOODLE_IOCTL_REQUEST* req = NULL;
  size_t reqLen = 0;
  NTSTATUS status = WdfRequestRetrieveInputBuffer(Request, sizeof(QUOODLE_IOCTL_REQUEST), (PVOID*)&req, &reqLen);
  if (!NT_SUCCESS(status) || req == NULL) {
    WdfRequestComplete(Request, STATUS_INVALID_PARAMETER);
    return;
  }

  // METHOD_BUFFERED can alias input/output into the same system buffer.
  // Copy request data first so response initialization cannot clobber fields
  // used for validation (e.g. timestamp_unix, opcode, signature).
  QUOODLE_IOCTL_REQUEST req_copy;
  RtlZeroMemory(&req_copy, sizeof(req_copy));
  RtlCopyMemory(&req_copy, req, sizeof(req_copy));

  QUOODLE_IOCTL_RESPONSE* resp = NULL;
  size_t respLen = 0;
  status = WdfRequestRetrieveOutputBuffer(Request, sizeof(QUOODLE_IOCTL_RESPONSE), (PVOID*)&resp, &respLen);
  if (!NT_SUCCESS(status) || resp == NULL) {
    WdfRequestComplete(Request, STATUS_INVALID_PARAMETER);
    return;
  }

  InitResponse(resp, req_copy.request_id);

  BOOLEAN should_emit_event = FALSE;
  const CHAR* runtime_reason_code = NULL;
  QUOODLE_OPCODE opcode = (QUOODLE_OPCODE)req_copy.opcode;
  LARGE_INTEGER perfFreq = {0};
  LARGE_INTEGER perfStart = KeQueryPerformanceCounter(&perfFreq);

  if (req_copy.version != QUOODLE_IOCTL_VERSION) {
    resp->error_code = QERR_INVALID_VERSION;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "invalid_version");
    runtime_reason_code = "invalid_version";
  } else if (!ValidateRequestPayload(&req_copy)) {
    resp->error_code = QERR_BAD_PAYLOAD;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "bad_payload");
    runtime_reason_code = "bad_payload";
  } else if (!IsTimestampFresh(req_copy.timestamp_unix)) {
    resp->error_code = QERR_TIMESTAMP_SKEW;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "timestamp_skew");
    runtime_reason_code = "timestamp_skew";
  } else if (!UpdateSequenceIfNew(req_copy.agent_sequence)) {
    resp->error_code = QERR_SEQ_REPLAY;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "seq_replay");
    runtime_reason_code = "seq_replay";
  } else if (!g_hmac_ready || g_hmac_key_len == 0) {
    resp->error_code = QERR_SIGNATURE_INVALID;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "signature_invalid");
    runtime_reason_code = "signature_invalid";
  } else if (req_copy.signature_length == 0) {
    resp->error_code = QERR_SIGNATURE_MISSING;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "signature_missing");
    runtime_reason_code = "signature_missing";
  } else if (req_copy.signature_length >= QUOODLE_MAX_SIG_B64 || req_copy.signature_b64[req_copy.signature_length] != '\0') {
    resp->error_code = QERR_BAD_PAYLOAD;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "bad_payload");
    runtime_reason_code = "bad_payload";
  } else if (!VerifyRequestSignature(&req_copy)) {
    resp->error_code = QERR_SIGNATURE_INVALID;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "signature_invalid");
    runtime_reason_code = "signature_invalid";
  } else {
    switch (opcode) {
      case QOP_EXEC_PING:
        HandlePing(resp);
        should_emit_event = TRUE;
        break;
      case QOP_EXEC_REBOOT:
        HandleReboot(resp);
        should_emit_event = TRUE;
        break;
      case QOP_EXEC_SHUTDOWN:
        HandleShutdown(resp);
        should_emit_event = TRUE;
        break;
      case QOP_EXEC_LOCK_SCREEN:
      case QOP_EXEC_LOGOUT:
      case QOP_EXEC_COLLECT_SYSTEM_INFO:
      case QOP_EXEC_GET_PROCESS_LIST:
      case QOP_EXEC_VALIDATE_UPDATE_PACKAGE:
      case QOP_STAGE_UPDATE:
      case QOP_COMMIT_UPDATE:
      case QOP_ROLLBACK_UPDATE:
      case QOP_EXEC_RUN_ATTESTATION:
      case QOP_EXEC_RUN_TAMPER_CHECK:
      case QOP_EXEC_SELF_REPAIR:
        HandleNotSupported(resp);
        should_emit_event = TRUE;
        break;
      default:
        resp->error_code = QERR_INVALID_OPCODE;
        RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "invalid_opcode");
        should_emit_event = TRUE;
        break;
    }
  }

  LARGE_INTEGER perfEnd = KeQueryPerformanceCounter(NULL);
  ULONGLONG duration_ms = 0;
  if (perfFreq.QuadPart > 0 && perfEnd.QuadPart >= perfStart.QuadPart) {
    duration_ms = (ULONGLONG)(((perfEnd.QuadPart - perfStart.QuadPart) * 1000ULL) / perfFreq.QuadPart);
  }

  SignResponse(resp);

  if (should_emit_event) {
    EmitOpcodeEvent(opcode, resp, duration_ms, req_copy.policy_hash);
  } else if (runtime_reason_code != NULL) {
    InterlockedIncrement64(&g_validation_rejects);
    EmitValidationRejectEvent(opcode, resp, runtime_reason_code, duration_ms, req_copy.policy_hash);
  }

  WdfRequestCompleteWithInformation(Request, STATUS_SUCCESS, sizeof(QUOODLE_IOCTL_RESPONSE));
}

static VOID QuoodleEvtDriverUnload(_In_ WDFDRIVER Driver) {
  UNREFERENCED_PARAMETER(Driver);
  DeleteUserSymbolicLinks();
  if (g_hmac_key_len > 0) {
    RtlSecureZeroMemory(g_hmac_key, sizeof(g_hmac_key));
    g_hmac_key_len = 0;
    g_hmac_ready = FALSE;
  }
}

static NTSTATUS QuoodleCreateDevice(_Inout_ PWDFDEVICE_INIT* DeviceInitInOut, _Out_ WDFDEVICE* DeviceOut) {
  if (!DeviceInitInOut || !*DeviceInitInOut || !DeviceOut) {
    return STATUS_INVALID_PARAMETER;
  }

  PWDFDEVICE_INIT DeviceInit = *DeviceInitInOut;

  WdfDeviceInitSetDeviceType(DeviceInit, FILE_DEVICE_UNKNOWN);
  WdfDeviceInitSetCharacteristics(DeviceInit, FILE_DEVICE_SECURE_OPEN, FALSE);

  UNICODE_STRING deviceName;
  RtlInitUnicodeString(&deviceName, QUOODLE_DEVICE_NAME);
  NTSTATUS status = WdfDeviceInitAssignName(DeviceInit, &deviceName);
  if (!NT_SUCCESS(status)) {
    return status;
  }

  WDFDEVICE device;
  status = WdfDeviceCreate(&DeviceInit, WDF_NO_OBJECT_ATTRIBUTES, &device);
  if (!NT_SUCCESS(status)) {
    *DeviceInitInOut = DeviceInit;
    return status;
  }
  *DeviceInitInOut = DeviceInit;

  status = WdfSpinLockCreate(WDF_NO_OBJECT_ATTRIBUTES, &g_event_lock);
  if (!NT_SUCCESS(status)) {
    goto CleanupDevice;
  }
  g_event_head = 0;
  g_event_tail = 0;
  g_event_count = 0;

  WDF_IO_QUEUE_CONFIG waitQueueConfig;
  WDF_IO_QUEUE_CONFIG_INIT(&waitQueueConfig, WdfIoQueueDispatchManual);
  status = WdfIoQueueCreate(device, &waitQueueConfig, WDF_NO_OBJECT_ATTRIBUTES, &g_wait_queue);
  if (!NT_SUCCESS(status)) {
    goto CleanupDevice;
  }

  WDF_IO_QUEUE_CONFIG queueConfig;
  WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(&queueConfig, WdfIoQueueDispatchSequential);
  queueConfig.EvtIoDeviceControl = QuoodleEvtIoDeviceControl;

  status = WdfIoQueueCreate(device, &queueConfig, WDF_NO_OBJECT_ATTRIBUTES, WDF_NO_HANDLE);
  if (!NT_SUCCESS(status)) {
    goto CleanupDevice;
  }

  *DeviceOut = device;
  return STATUS_SUCCESS;

CleanupDevice:
  WdfObjectDelete(device);
  return status;
}

NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath) {
  WDF_DRIVER_CONFIG config;
  WDF_DRIVER_CONFIG_INIT(&config, WDF_NO_EVENT_CALLBACK);
  config.DriverInitFlags |= WdfDriverInitNonPnpDriver;
  config.EvtDriverUnload = QuoodleEvtDriverUnload;

  WDFDRIVER driver = NULL;
  NTSTATUS status = WdfDriverCreate(DriverObject, RegistryPath, WDF_NO_OBJECT_ATTRIBUTES, &config, &driver);
  if (!NT_SUCCESS(status)) {
    return status;
  }

  UNICODE_STRING sddl;
  RtlInitUnicodeString(&sddl, L"D:P(A;;GA;;;SY)(A;;GA;;;BA)");
  PWDFDEVICE_INIT controlInit = WdfControlDeviceInitAllocate(driver, &sddl);
  if (controlInit == NULL) {
    return STATUS_INSUFFICIENT_RESOURCES;
  }

  WDFDEVICE controlDevice = NULL;
  status = QuoodleCreateDevice(&controlInit, &controlDevice);
  if (!NT_SUCCESS(status)) {
    if (controlInit != NULL) {
      WdfDeviceInitFree(controlInit);
    }
    return status;
  }

  WdfControlFinishInitializing(controlDevice);

  status = CreateUserSymbolicLinks();
  if (!NT_SUCCESS(status)) {
    WdfObjectDelete(controlDevice);
    return status;
  }

  // Load once at startup (secure config path: service registry parameters).
  (void)LoadHmacKeyFromRegistry(RegistryPath);

  return STATUS_SUCCESS;
}
