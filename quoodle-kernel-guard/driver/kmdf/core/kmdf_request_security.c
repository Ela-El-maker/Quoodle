#include <ntddk.h>
#include <ntstrsafe.h>

#include "kmdf_request_security.h"

#define QUOODLE_TAG 'Qood'
#define QUOODLE_MAX_CANONICAL 2048
#define QUOODLE_HMAC_KEY_MAX 128

typedef struct _QSHA256_CTX {
  UINT32 state[8];
  UINT64 bitlen;
  UINT32 datalen;
  UCHAR data[64];
} QSHA256_CTX;

static volatile LONGLONG g_last_seq = 0;
static UCHAR g_hmac_key[QUOODLE_HMAC_KEY_MAX];
static ULONG g_hmac_key_len = 0;
static BOOLEAN g_hmac_ready = FALSE;

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

static SIZE_T qrs_strnlen_a(const CHAR* s, SIZE_T max_len) {
  SIZE_T len = 0;
  if (!s) {
    return 0;
  }
  while (len < max_len && s[len] != '\0') {
    len++;
  }
  return len;
}

static uint64_t qrs_unix_timestamp_seconds(void) {
  LARGE_INTEGER system_time;
  KeQuerySystemTime(&system_time);
  const LONGLONG epoch_delta = 116444736000000000LL;
  if (system_time.QuadPart < epoch_delta) {
    return 0;
  }
  return (uint64_t)((system_time.QuadPart - epoch_delta) / 10000000ULL);
}

static BOOLEAN qrs_is_null_terminated_a(const CHAR* s, SIZE_T cap) {
  SIZE_T i;
  if (!s || cap == 0) {
    return FALSE;
  }
  for (i = 0; i < cap; ++i) {
    if (s[i] == '\0') {
      return TRUE;
    }
  }
  return FALSE;
}

static VOID qsha256_transform(QSHA256_CTX* ctx, const UCHAR data[64]) {
  UINT32 a, b, c, d, e, f, g, h, i, j, t1, t2, m[64];

  for (i = 0, j = 0; i < 16; ++i, j += 4) {
    m[i] = ((UINT32)data[j] << 24) | ((UINT32)data[j + 1] << 16) | ((UINT32)data[j + 2] << 8) | ((UINT32)data[j + 3]);
  }
  for (; i < 64; ++i) {
    UINT32 s0 = qrotr(m[i - 15], 7) ^ qrotr(m[i - 15], 18) ^ (m[i - 15] >> 3);
    UINT32 s1 = qrotr(m[i - 2], 17) ^ qrotr(m[i - 2], 19) ^ (m[i - 2] >> 10);
    m[i] = m[i - 16] + s0 + m[i - 7] + s1;
  }

  a = ctx->state[0];
  b = ctx->state[1];
  c = ctx->state[2];
  d = ctx->state[3];
  e = ctx->state[4];
  f = ctx->state[5];
  g = ctx->state[6];
  h = ctx->state[7];

  for (i = 0; i < 64; ++i) {
    UINT32 s1 = qrotr(e, 6) ^ qrotr(e, 11) ^ qrotr(e, 25);
    UINT32 ch = (e & f) ^ ((~e) & g);
    t1 = h + s1 + ch + qsha_k[i] + m[i];
    UINT32 s0 = qrotr(a, 2) ^ qrotr(a, 13) ^ qrotr(a, 22);
    UINT32 maj = (a & b) ^ (a & c) ^ (b & c);
    t2 = s0 + maj;

    h = g;
    g = f;
    f = e;
    e = d + t1;
    d = c;
    c = b;
    b = a;
    a = t1 + t2;
  }

  ctx->state[0] += a;
  ctx->state[1] += b;
  ctx->state[2] += c;
  ctx->state[3] += d;
  ctx->state[4] += e;
  ctx->state[5] += f;
  ctx->state[6] += g;
  ctx->state[7] += h;
}

static VOID qsha256_init(QSHA256_CTX* ctx) {
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

static VOID qsha256_update(QSHA256_CTX* ctx, const UCHAR* data, SIZE_T len) {
  SIZE_T i;
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

static VOID qsha256_final(QSHA256_CTX* ctx, UCHAR out[32]) {
  UINT32 i = ctx->datalen;

  if (ctx->datalen < 56) {
    ctx->data[i++] = 0x80;
    while (i < 56) {
      ctx->data[i++] = 0x00;
    }
  } else {
    ctx->data[i++] = 0x80;
    while (i < 64) {
      ctx->data[i++] = 0x00;
    }
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

static VOID qhmac_sha256(const UCHAR* key, SIZE_T key_len, const UCHAR* msg, SIZE_T msg_len, UCHAR out[32]) {
  UCHAR k_ipad[64];
  UCHAR k_opad[64];
  UCHAR tk[32];
  SIZE_T i;

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
  ULONG i = 0;
  ULONG j = 0;
  UINT32 val = 0;
  INT valb = -8;
  while (i < in_len) {
    CHAR c = in[i++];
    if (c == '=') {
      break;
    }
    INT d = q_b64_index(c);
    if (d < 0) {
      return FALSE;
    }
    val = (val << 6) | (UINT32)d;
    valb += 6;
    if (valb >= 0) {
      if (j >= out_cap) {
        return FALSE;
      }
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
  if (out_cap < olen + 1) {
    return FALSE;
  }

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
  for (i = 0; i < len; ++i) {
    diff |= (a[i] ^ b[i]);
  }
  return diff == 0;
}

static NTSTATUS qrs_build_canonical_request(const QUOODLE_IOCTL_REQUEST* req, CHAR* out, SIZE_T out_cap, SIZE_T* out_len) {
  NTSTATUS st;
  SIZE_T req_id_len = qrs_strnlen_a(req->request_id, sizeof(req->request_id));
  SIZE_T cmd_len = qrs_strnlen_a(req->command_message_id, sizeof(req->command_message_id));
  SIZE_T policy_len = qrs_strnlen_a(req->policy_hash, sizeof(req->policy_hash));

  st = RtlStringCchPrintfA(
      out,
      out_cap,
      "v1\nseq=%I64u\ncmd=%u:%.*s\nop=%u\nparams=%u:%.*s\npolicy=%u:%.*s\nreq=%u:%.*s\nts=%I64u\n",
      req->agent_sequence,
      (UINT32)cmd_len,
      (INT)cmd_len,
      req->command_message_id,
      req->opcode,
      req->params_length,
      (INT)req->params_length,
      req->params_json,
      (UINT32)policy_len,
      (INT)policy_len,
      req->policy_hash,
      (UINT32)req_id_len,
      (INT)req_id_len,
      req->request_id,
      req->timestamp_unix);
  if (!NT_SUCCESS(st)) {
    return STATUS_BUFFER_TOO_SMALL;
  }

  *out_len = qrs_strnlen_a(out, out_cap);
  return STATUS_SUCCESS;
}

static NTSTATUS qrs_build_canonical_response(const QUOODLE_IOCTL_RESPONSE* resp, CHAR* out, SIZE_T out_cap, SIZE_T* out_len) {
  NTSTATUS st;
  SIZE_T req_id_len = qrs_strnlen_a(resp->request_id, sizeof(resp->request_id));
  SIZE_T kexec_len = qrs_strnlen_a(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
  SIZE_T err_len = qrs_strnlen_a(resp->error_message, sizeof(resp->error_message));

  st = RtlStringCchPrintfA(
      out,
      out_cap,
      "v1\nstatus=%u\nerror=%u\nkexec=%u:%.*s\nreq=%u:%.*s\nresult=%u:%.*s\nmsg=%u:%.*s\nts=%I64u\n",
      resp->status,
      resp->error_code,
      (UINT32)kexec_len,
      (INT)kexec_len,
      resp->kernel_exec_id,
      (UINT32)req_id_len,
      (INT)req_id_len,
      resp->request_id,
      resp->result_length,
      (INT)resp->result_length,
      resp->result_json,
      (UINT32)err_len,
      (INT)err_len,
      resp->error_message,
      resp->timestamp_unix);
  if (!NT_SUCCESS(st)) {
    return STATUS_BUFFER_TOO_SMALL;
  }

  *out_len = qrs_strnlen_a(out, out_cap);
  return STATUS_SUCCESS;
}

VOID QuoodleRequestSecurityInitResponse(_Out_ QUOODLE_IOCTL_RESPONSE* resp, _In_opt_ const CHAR* request_id) {
  RtlZeroMemory(resp, sizeof(*resp));
  resp->version = QUOODLE_IOCTL_VERSION;
  resp->timestamp_unix = qrs_unix_timestamp_seconds();
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

BOOLEAN QuoodleRequestSecurityValidatePayload(_In_ const QUOODLE_IOCTL_REQUEST* req) {
  if (!req) return FALSE;
  if (!qrs_is_null_terminated_a(req->request_id, sizeof(req->request_id))) return FALSE;
  if (!qrs_is_null_terminated_a(req->policy_hash, sizeof(req->policy_hash))) return FALSE;
  if (!qrs_is_null_terminated_a(req->command_message_id, sizeof(req->command_message_id))) return FALSE;
  if (!qrs_is_null_terminated_a(req->signature_b64, sizeof(req->signature_b64))) return FALSE;

  if (req->params_length >= QUOODLE_MAX_PARAMS) return FALSE;
  if (!qrs_is_null_terminated_a(req->params_json, sizeof(req->params_json))) return FALSE;
  if (req->params_json[req->params_length] != '\0') return FALSE;

  return TRUE;
}

BOOLEAN QuoodleRequestSecurityIsTimestampFresh(_In_ uint64_t ts) {
  uint64_t now = qrs_unix_timestamp_seconds();
  if (ts > now) {
    return (ts - now) <= QUOODLE_ALLOWED_TIMESTAMP_SKEW_SEC;
  }
  return (now - ts) <= QUOODLE_ALLOWED_TIMESTAMP_SKEW_SEC;
}

BOOLEAN QuoodleRequestSecurityUpdateSequenceIfNew(_In_ uint64_t seq) {
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

BOOLEAN QuoodleRequestSecurityHasHmacKey(VOID) {
  return (BOOLEAN)(g_hmac_ready && g_hmac_key_len > 0);
}

BOOLEAN QuoodleRequestSecurityVerifyRequestSignature(_In_ const QUOODLE_IOCTL_REQUEST* req) {
  UCHAR provided[64];
  ULONG provided_len = 0;
  UCHAR expected[QUOODLE_HMAC_SHA256_BYTES];
  CHAR canonical[QUOODLE_MAX_CANONICAL];
  SIZE_T canonical_len = 0;

  if (!QuoodleRequestSecurityHasHmacKey()) {
    return FALSE;
  }

  if (!q_base64_decode(req->signature_b64, req->signature_length, provided, sizeof(provided), &provided_len)) {
    return FALSE;
  }
  if (provided_len != QUOODLE_HMAC_SHA256_BYTES) {
    return FALSE;
  }

  if (!NT_SUCCESS(qrs_build_canonical_request(req, canonical, sizeof(canonical), &canonical_len))) {
    return FALSE;
  }

  qhmac_sha256(g_hmac_key, g_hmac_key_len, (const UCHAR*)canonical, canonical_len, expected);
  return q_const_time_eq(provided, expected, QUOODLE_HMAC_SHA256_BYTES);
}

VOID QuoodleRequestSecuritySignResponse(_Inout_ QUOODLE_IOCTL_RESPONSE* resp) {
  UCHAR digest[QUOODLE_HMAC_SHA256_BYTES];
  CHAR canonical[QUOODLE_MAX_CANONICAL];
  SIZE_T canonical_len = 0;
  ULONG sig_len = 0;

  resp->signature_length = 0;
  resp->signature_b64[0] = '\0';

  if (!QuoodleRequestSecurityHasHmacKey()) {
    return;
  }

  if (!NT_SUCCESS(qrs_build_canonical_response(resp, canonical, sizeof(canonical), &canonical_len))) {
    return;
  }

  qhmac_sha256(g_hmac_key, g_hmac_key_len, (const UCHAR*)canonical, canonical_len, digest);
  if (q_base64_encode(digest, sizeof(digest), resp->signature_b64, sizeof(resp->signature_b64), &sig_len)) {
    resp->signature_length = sig_len;
  }
  RtlSecureZeroMemory(digest, sizeof(digest));
}

NTSTATUS QuoodleRequestSecurityLoadHmacKeyFromRegistry(_In_ PUNICODE_STRING RegistryPath) {
  WCHAR params_path_buf[512];
  UNICODE_STRING params_path;
  HANDLE key = NULL;
  OBJECT_ATTRIBUTES oa;
  UNICODE_STRING value_name;
  NTSTATUS status;
  ULONG needed = 0;
  PKEY_VALUE_PARTIAL_INFORMATION kvpi = NULL;

  if (!RegistryPath || !RegistryPath->Buffer) {
    return STATUS_INVALID_PARAMETER;
  }

  status = RtlStringCchPrintfW(params_path_buf, RTL_NUMBER_OF(params_path_buf), L"%wZ\\Parameters", RegistryPath);
  if (!NT_SUCCESS(status)) {
    return STATUS_BUFFER_TOO_SMALL;
  }

  RtlInitUnicodeString(&params_path, params_path_buf);
  InitializeObjectAttributes(&oa, &params_path, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);

  status = ZwOpenKey(&key, KEY_READ, &oa);
  if (!NT_SUCCESS(status)) {
    return status;
  }

  RtlInitUnicodeString(&value_name, L"HmacKey");
  status = ZwQueryValueKey(key, &value_name, KeyValuePartialInformation, NULL, 0, &needed);
  if (status != STATUS_BUFFER_TOO_SMALL && status != STATUS_BUFFER_OVERFLOW) {
    ZwClose(key);
    return status;
  }

  kvpi = (PKEY_VALUE_PARTIAL_INFORMATION)ExAllocatePool2(POOL_FLAG_NON_PAGED, needed, QUOODLE_TAG);
  if (!kvpi) {
    ZwClose(key);
    return STATUS_INSUFFICIENT_RESOURCES;
  }

  status = ZwQueryValueKey(key, &value_name, KeyValuePartialInformation, kvpi, needed, &needed);
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

VOID QuoodleRequestSecurityClearKey(VOID) {
  if (g_hmac_key_len > 0) {
    RtlSecureZeroMemory(g_hmac_key, sizeof(g_hmac_key));
  }
  g_hmac_key_len = 0;
  g_hmac_ready = FALSE;
}