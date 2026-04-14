#include "opcode_map.hpp"

namespace kernel::opcodes
{

QuoodleOpcode MapOpcodeToCode(const std::string &opcode)
{
  if (opcode == "EXEC_LOCK_SCREEN")
    return QOP_EXEC_LOCK_SCREEN;
  if (opcode == "EXEC_REBOOT")
    return QOP_EXEC_REBOOT;
  if (opcode == "EXEC_SHUTDOWN")
    return QOP_EXEC_SHUTDOWN;
  if (opcode == "EXEC_LOGOUT")
    return QOP_EXEC_LOGOUT;
  if (opcode == "EXEC_PING_KERNEL" || opcode == "ping")
    return QOP_EXEC_PING;
  if (opcode == "EXEC_COLLECT_SYSTEM_INFO" || opcode == "COLLECT_SYSTEM_INFO")
    return QOP_EXEC_COLLECT_SYSTEM_INFO;
  if (opcode == "list_processes" || opcode == "LIST_PROCESSES")
    return QOP_OBS_LIST_PROCESSES;
  if (opcode == "EXEC_GET_PROCESS_LIST" || opcode == "GET_PROCESS_LIST")
    return QOP_EXEC_GET_PROCESS_LIST;
  if (opcode == "list_services" || opcode == "LIST_SERVICES")
    return QOP_OBS_LIST_SERVICES;
  if (opcode == "list_connections" || opcode == "LIST_CONNECTIONS")
    return QOP_OBS_LIST_CONNECTIONS;
  if (opcode == "list_mounts" || opcode == "LIST_MOUNTS")
    return QOP_OBS_LIST_MOUNTS;
  if (opcode == "network_info" || opcode == "NETWORK_INFO")
    return QOP_OBS_NETWORK_INFO;
  if (opcode == "get_active_window" || opcode == "GET_ACTIVE_WINDOW")
    return QOP_OBS_GET_ACTIVE_WINDOW;
  if (opcode == "list_files" || opcode == "LIST_FILES")
    return QOP_FS_LIST_FILES;
  if (opcode == "download_file" || opcode == "DOWNLOAD_FILE")
    return QOP_FS_DOWNLOAD_FILE;
  if (opcode == "SEC_APPLOCK_REPLACE_POLICY")
    return QOP_SEC_APPLOCK_REPLACE_POLICY;
  if (opcode == "SEC_APPLOCK_GET_STATUS")
    return QOP_SEC_APPLOCK_GET_STATUS;
  if (opcode == "SEC_APPLOCK_CLEAR_POLICY")
    return QOP_SEC_APPLOCK_CLEAR_POLICY;
  if (opcode == "EXEC_VALIDATE_UPDATE_PACKAGE" || opcode == "VALIDATE_UPDATE_PACKAGE")
    return QOP_EXEC_VALIDATE_UPDATE_PACKAGE;
  if (opcode == "EXEC_CAPTURE_SCREENSHOT" || opcode == "CAPTURE_SCREENSHOT" || opcode == "screenshot")
    return QOP_EXEC_CAPTURE_SCREENSHOT;
  if (opcode == "STAGE_UPDATE")
    return QOP_STAGE_UPDATE;
  if (opcode == "COMMIT_UPDATE")
    return QOP_COMMIT_UPDATE;
  if (opcode == "ROLLBACK_UPDATE")
    return QOP_ROLLBACK_UPDATE;
  if (opcode == "EXEC_RUN_ATTESTATION" || opcode == "RUN_ATTESTATION")
    return QOP_EXEC_RUN_ATTESTATION;
  if (opcode == "EXEC_RUN_TAMPER_CHECK" || opcode == "RUN_TAMPER_CHECK")
    return QOP_EXEC_RUN_TAMPER_CHECK;
  if (opcode == "EXEC_SELF_REPAIR" || opcode == "SELF_REPAIR")
    return QOP_EXEC_SELF_REPAIR;
  return QOP_UNKNOWN;
}

} // namespace kernel::opcodes
