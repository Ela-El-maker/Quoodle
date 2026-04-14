#pragma once

#include <string>
#include <cstdint>
#ifdef _WIN32
#include <windows.h>
#endif
#include "driver_ioctl.hpp"

class AgentState; // Forward declaration

/**
 * KernelExecResult
 * Represents the structured response from the privileged kernel service.
 * Aligned with the project's JSON communication spec.
 */
struct KernelExecResult
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
 * IoctlClient
 * The gateway for the User-Mode Agent to request privileged operations.
 * It abstracts the IPC (Inter-Process Communication) layer.
 *
 * All requests are signed with Ed25519 and include:
 *   - request_id: Unique identifier
 *   - timestamp: ISO 8601 UTC
 *   - opcode: Operation to execute
 *   - params: JSON parameters
 *   - agent_sequence: Monotonic counter (replay protection)
 *   - policy_hash: Current policy hash
 *   - command_message_id: Originating command from controller
 *   - signature: Ed25519 signature over canonical payload
 */
class IoctlClient
{
public:
  IoctlClient() = default;
  ~IoctlClient();

  // Public API for supported Kernel operations
  // Each method accepts agent state for policy_hash and generates signed requests.
  KernelExecResult lock_screen(const std::string &request_id, const AgentState &state,
                               const std::string &command_message_id = "");
  KernelExecResult ping(const std::string &request_id, const AgentState &state,
                        const std::string &command_message_id = "");
  KernelExecResult reboot(const std::string &request_id, const AgentState &state,
                          const std::string &command_message_id = "");
  KernelExecResult shutdown(const std::string &request_id, const AgentState &state,
                            const std::string &command_message_id = "");
  KernelExecResult logout(const std::string &request_id, const AgentState &state,
                          const std::string &command_message_id = "");
  KernelExecResult collect_system_info(const std::string &request_id, const AgentState &state,
                                       const std::string &command_message_id = "",
                                       const std::string &params_json = "{}");
  KernelExecResult capture_screenshot_authorize(const std::string &request_id, const AgentState &state,
                                                const std::string &command_message_id = "",
                                                const std::string &params_json = "{}");
  KernelExecResult get_process_list(const std::string &request_id, const AgentState &state,
                                    const std::string &command_message_id = "");
  KernelExecResult list_services(const std::string &request_id, const AgentState &state,
                                 const std::string &command_message_id = "");
  KernelExecResult list_connections(const std::string &request_id, const AgentState &state,
                                    const std::string &command_message_id = "");
  KernelExecResult list_mounts(const std::string &request_id, const AgentState &state,
                               const std::string &command_message_id = "");
  KernelExecResult network_info(const std::string &request_id, const AgentState &state,
                                const std::string &command_message_id = "");
  KernelExecResult get_active_window(const std::string &request_id, const AgentState &state,
                                     const std::string &command_message_id = "");
  KernelExecResult list_files(const std::string &request_id, const AgentState &state,
                              const std::string &params_json = "{}",
                              const std::string &command_message_id = "");
  KernelExecResult download_file(const std::string &request_id, const AgentState &state,
                                 const std::string &params_json = "{}",
                                 const std::string &command_message_id = "");
  KernelExecResult applock_replace_policy(const std::string &request_id, const AgentState &state,
                                          const std::string &policy_blob,
                                          const std::string &command_message_id = "");
  KernelExecResult applock_get_status(const std::string &request_id, const AgentState &state,
                                      const std::string &command_message_id = "");
  KernelExecResult applock_clear_policy(const std::string &request_id, const AgentState &state,
                                        const std::string &command_message_id = "");
  KernelExecResult validate_update_package(const std::string &request_id, const AgentState &state,
                                           const std::string &package_path,
                                           const std::string &command_message_id = "");
  KernelExecResult stage_update(const std::string &request_id, const AgentState &state,
                                const std::string &version, const std::string &package_path,
                                const std::string &command_message_id = "");
  KernelExecResult commit_update(const std::string &request_id, const AgentState &state,
                                 const std::string &command_message_id = "");
  KernelExecResult rollback_update(const std::string &request_id, const AgentState &state,
                                   const std::string &reason = "",
                                   const std::string &command_message_id = "");
  KernelExecResult run_attestation(const std::string &request_id, const AgentState &state,
                                   const std::string &command_message_id = "");
  KernelExecResult run_tamper_check(const std::string &request_id, const AgentState &state,
                                    const std::string &command_message_id = "");
  KernelExecResult self_repair(const std::string &request_id, const AgentState &state,
                               const std::string &component = "",
                               const std::string &command_message_id = "");

  // True when the most recent connected execution path is the kernel driver IOCTL transport.
  bool using_driver_transport() const;
  // True when the most recent connected execution path is the named pipe fallback transport.
  bool using_pipe_transport() const;
  // Last transport-layer error code/message emitted by the client path.
  int last_transport_error_code() const;
  std::string last_transport_error_message() const;
  int last_transport_win32_error() const;

private:
  bool ensure_connection(); // Helper to reconnect if pipe drops
  void disconnect();
  KernelExecResult execute_empty_params_opcode(const std::string &opcode, const std::string &request_id,
                                               const AgentState &state, const std::string &command_message_id);

  // Core communication handler (Pipe + Fallback)
  std::string execute_request(const std::string &opcode, const std::string &request_id,
                              const std::string &params_json, const AgentState &state,
                              const std::string &command_message_id);

  // Internal JSON parsing
  KernelExecResult parse_result_from_json(const std::string &json);

  // Parse and verify kernel response signature
  KernelExecResult parse_and_verify_response(const std::string &json, const std::string &request_id);

  // Build canonical payload for signing (fields in lexicographic order)
  std::string build_canonical_payload(const std::string &request_id, const std::string &timestamp,
                                      const std::string &opcode, const std::string &params,
                                      std::uint64_t agent_sequence, const std::string &policy_hash,
                                      const std::string &command_message_id);

  // Get next sequence number (thread-safe, monotonic)
  std::uint64_t next_sequence();

#ifdef _WIN32
  HANDLE hPipe = INVALID_HANDLE_VALUE;
  HANDLE hDevice = INVALID_HANDLE_VALUE;
  bool useDevice = false;
#endif
  int last_transport_error_code_{-1};
  std::string last_transport_error_message_{"ipc_failure"};
  int last_transport_win32_error_{0};
};
