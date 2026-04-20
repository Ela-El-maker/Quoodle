#pragma once

#include <string>
#include <vector>
#include <unordered_map>

struct KernelResponse
{
  std::string request_id;
  std::string status;
  std::string kernel_exec_id;
  std::string timestamp;
  std::string result;
  int error_code{0};
  std::string error_message;
  std::string sig;
};

/**
 * Dispatcher routes incoming opcode requests to the appropriate handler.
 * All 14 opcodes from the spec are implemented:
 *
 * SystemControl:
 *   - EXEC_LOCK_SCREEN, EXEC_REBOOT, EXEC_SHUTDOWN, EXEC_LOGOUT
 *
 * AgentInternal:
 *   - EXEC_PING_KERNEL, EXEC_COLLECT_SYSTEM_INFO, EXEC_GET_PROCESS_LIST, EXEC_VALIDATE_UPDATE_PACKAGE
 *   - EXEC_KILL_PROCESS
 *
 * UpdateAndStaging:
 *   - STAGE_UPDATE, COMMIT_UPDATE, ROLLBACK_UPDATE
 *
 * SecurityIntegrity:
 *   - EXEC_RUN_ATTESTATION, EXEC_RUN_TAMPER_CHECK, EXEC_SELF_REPAIR
 */
class Dispatcher
{
public:
  // ============== SystemControl ==============
  KernelResponse handle_lock_screen(const std::string &request_id);
  KernelResponse handle_reboot(const std::string &request_id, int delay_seconds);
  KernelResponse handle_shutdown(const std::string &request_id, bool force);
  KernelResponse handle_logout(const std::string &request_id);

  // ============== AgentInternal ==============
  KernelResponse handle_ping(const std::string &request_id);
  KernelResponse handle_collect_system_info(const std::string &request_id, const std::vector<std::string> &fields);
  KernelResponse handle_get_process_list(const std::string &request_id, bool include_cmdline);
  KernelResponse handle_kill_process(const std::string &request_id, int pid);
  KernelResponse handle_validate_update_package(const std::string &request_id, const std::string &path);

  // ============== UpdateAndStaging ==============
  KernelResponse handle_stage_update(const std::string &request_id, const std::string &package_path, bool sandbox);
  KernelResponse handle_commit_update(const std::string &request_id, const std::string &sandbox_id);
  KernelResponse handle_rollback_update(const std::string &request_id, const std::string &snapshot_id);

  // ============== SecurityIntegrity ==============
  KernelResponse handle_run_attestation(const std::string &request_id, bool include_tpm);
  KernelResponse handle_run_tamper_check(const std::string &request_id);
  KernelResponse handle_self_repair(const std::string &request_id);

  // ============== Fallback ==============
  KernelResponse handle_unknown(const std::string &request_id, const std::string &opcode);
};
