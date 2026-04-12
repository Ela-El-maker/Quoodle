#include "../ioctl_client.hpp"

namespace
{

KernelExecResult make_error_result(const std::string &request_id, int code, const std::string &message)
{
  return {request_id, "error", "", "", "", code, message, ""};
}

} // namespace

KernelExecResult IoctlClient::execute_empty_params_opcode(const std::string &opcode, const std::string &request_id,
                                                          const AgentState &state, const std::string &command_message_id)
{
  std::string json = execute_request(opcode, request_id, "{}", state, command_message_id);
  if (json.empty())
  {
    return make_error_result(request_id, last_transport_error_code_, last_transport_error_message_);
  }
  return parse_and_verify_response(json, request_id);
}

KernelExecResult IoctlClient::lock_screen(const std::string &request_id, const AgentState &state,
                                          const std::string &command_message_id)
{
  return execute_empty_params_opcode("EXEC_LOCK_SCREEN", request_id, state, command_message_id);
}

KernelExecResult IoctlClient::ping(const std::string &request_id, const AgentState &state,
                                   const std::string &command_message_id)
{
  return execute_empty_params_opcode("ping", request_id, state, command_message_id);
}

KernelExecResult IoctlClient::reboot(const std::string &request_id, const AgentState &state,
                                     const std::string &command_message_id)
{
  return execute_empty_params_opcode("EXEC_REBOOT", request_id, state, command_message_id);
}

KernelExecResult IoctlClient::shutdown(const std::string &request_id, const AgentState &state,
                                       const std::string &command_message_id)
{
  return execute_empty_params_opcode("EXEC_SHUTDOWN", request_id, state, command_message_id);
}

KernelExecResult IoctlClient::logout(const std::string &request_id, const AgentState &state,
                                     const std::string &command_message_id)
{
  return execute_empty_params_opcode("EXEC_LOGOUT", request_id, state, command_message_id);
}
