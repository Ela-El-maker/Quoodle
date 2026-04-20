#pragma once

// Shared IOCTL definitions for Quoodle kernel driver (Windows).
// Keep this header plain C so it can be included by both kernel and user-mode.

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_KERNEL_MODE)
typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long long uint64_t;
#else
#include <stdint.h>
#endif

// Device name and user-mode symlink.
#define QUOODLE_DEVICE_NAME      L"\\Device\\QuoodleKernel"
#define QUOODLE_DOS_DEVICE_NAME  L"\\DosDevices\\Global\\QuoodleKernel"
#define QUOODLE_DOS_DEVICE_NAME_LEGACY L"\\DosDevices\\QuoodleKernel"

// IOCTL definitions
#ifndef CTL_CODE
#define CTL_CODE(DeviceType, Function, Method, Access) (                 \
  ((DeviceType) << 16) | ((Access) << 14) | ((Function) << 2) | (Method) \
)
#endif

#ifndef FILE_DEVICE_UNKNOWN
#define FILE_DEVICE_UNKNOWN 0x00000022
#endif

#ifndef FILE_ANY_ACCESS
#define FILE_ANY_ACCESS 0
#endif

#ifndef METHOD_BUFFERED
#define METHOD_BUFFERED 0
#endif

#define IOCTL_QUOODLE_EXECUTE CTL_CODE(FILE_DEVICE_UNKNOWN, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_QUOODLE_WAIT_EVENT CTL_CODE(FILE_DEVICE_UNKNOWN, 0x802, METHOD_BUFFERED, FILE_ANY_ACCESS)

// Protocol constants
#define QUOODLE_IOCTL_VERSION 2
#define QUOODLE_MAX_REQUEST_ID 64
#define QUOODLE_MAX_COMMAND_ID 64
#define QUOODLE_MAX_POLICY_HASH 128
#define QUOODLE_MAX_PARAMS 512
#define QUOODLE_MAX_RESULT 2048
#define QUOODLE_MAX_SIG_B64 128
#define QUOODLE_MAX_EVENT_PAYLOAD 512

// Transport hardening constants
#define QUOODLE_HMAC_SHA256_BYTES 32
#define QUOODLE_ALLOWED_TIMESTAMP_SKEW_SEC 300

// Standardized transport error codes (opcode-agnostic)
#define QERR_SEQ_REPLAY 2001
#define QERR_SIGNATURE_MISSING 2002
#define QERR_SIGNATURE_INVALID 2003
#define QERR_TIMESTAMP_SKEW 2004
#define QERR_BAD_PAYLOAD 2005
#define QERR_INVALID_OPCODE 4002
#define QERR_INVALID_VERSION 4003
#define QERR_NOT_SUPPORTED 4004
#define QERR_COLLECT_INFO_FAILED 5101
#define QERR_COLLECT_INFO_PAYLOAD_TOO_LARGE 5102

#include "quoodle_collect_info_contract.h"

typedef enum QUOODLE_KERNEL_EVENT_TYPE {
  QKEVENT_TYPE_OPCODE = 1,
  QKEVENT_TYPE_RUNTIME = 2,
  QKEVENT_TYPE_INTEGRITY = 3,
  QKEVENT_TYPE_ATTESTATION = 4,
  QKEVENT_TYPE_UPDATE = 5
} QUOODLE_KERNEL_EVENT_TYPE;

// Opcodes (keep aligned with spec allowlist)
typedef enum QUOODLE_OPCODE {
  QOP_UNKNOWN = 0,
  QOP_EXEC_LOCK_SCREEN = 1,
  QOP_EXEC_REBOOT = 2,
  QOP_EXEC_SHUTDOWN = 3,
  QOP_EXEC_LOGOUT = 4,
  QOP_EXEC_PING = 10,
  QOP_EXEC_COLLECT_SYSTEM_INFO = 11,
  QOP_EXEC_GET_PROCESS_LIST = 12,
  QOP_EXEC_VALIDATE_UPDATE_PACKAGE = 13,
  QOP_EXEC_CAPTURE_SCREENSHOT = 14,
  QOP_EXEC_KILL_PROCESS = 15,
  QOP_STAGE_UPDATE = 20,
  QOP_COMMIT_UPDATE = 21,
  QOP_ROLLBACK_UPDATE = 22,
  QOP_EXEC_RUN_ATTESTATION = 30,
  QOP_EXEC_RUN_TAMPER_CHECK = 31,
  QOP_EXEC_SELF_REPAIR = 32,
  // Category-masked observability opcodes (additive, v2-compatible).
  QOP_OBS_LIST_PROCESSES = ((1u << 16) | 1u),
  QOP_OBS_LIST_SERVICES = ((1u << 16) | 2u),
  QOP_OBS_LIST_CONNECTIONS = ((1u << 16) | 3u),
  QOP_OBS_LIST_MOUNTS = ((1u << 16) | 4u),
  QOP_OBS_NETWORK_INFO = ((1u << 16) | 5u),
  QOP_OBS_GET_ACTIVE_WINDOW = ((1u << 16) | 6u),
  // Category-masked filesystem opcodes (read-oriented).
  QOP_FS_LIST_FILES = ((2u << 16) | 1u),
  QOP_FS_DOWNLOAD_FILE = ((2u << 16) | 2u),
  // Category-masked security opcodes (policy-driven enforcement).
  QOP_SEC_APPLOCK_REPLACE_POLICY = ((5u << 16) | 1u),
  QOP_SEC_APPLOCK_GET_STATUS = ((5u << 16) | 2u),
  QOP_SEC_APPLOCK_CLEAR_POLICY = ((5u << 16) | 3u)
} QUOODLE_OPCODE;

typedef struct QUOODLE_IOCTL_REQUEST {
  uint32_t version;
  uint32_t opcode;
  uint32_t flags;
  uint32_t params_length;
  uint64_t agent_sequence;
  uint64_t timestamp_unix;
  char request_id[QUOODLE_MAX_REQUEST_ID];
  char policy_hash[QUOODLE_MAX_POLICY_HASH];
  char command_message_id[QUOODLE_MAX_COMMAND_ID];
  char params_json[QUOODLE_MAX_PARAMS];
  uint32_t signature_length;
  char signature_b64[QUOODLE_MAX_SIG_B64];
} QUOODLE_IOCTL_REQUEST;

typedef struct QUOODLE_IOCTL_RESPONSE {
  uint32_t version;
  uint32_t status;        // 0 = ok, nonzero = error
  uint32_t error_code;    // aligned with KernelErrorCodes
  uint32_t result_length;
  uint64_t timestamp_unix;
  char request_id[QUOODLE_MAX_REQUEST_ID];
  char kernel_exec_id[QUOODLE_MAX_REQUEST_ID];
  char error_message[128];
  char result_json[QUOODLE_MAX_RESULT];
  uint32_t signature_length;
  char signature_b64[QUOODLE_MAX_SIG_B64];
} QUOODLE_IOCTL_RESPONSE;

typedef struct QUOODLE_KERNEL_EVENT {
  uint64_t event_id;
  uint32_t event_type;
  uint64_t timestamp_unix;
  uint32_t payload_length;
  char payload_json[QUOODLE_MAX_EVENT_PAYLOAD];
} QUOODLE_KERNEL_EVENT;

#ifdef __cplusplus
}
#endif
