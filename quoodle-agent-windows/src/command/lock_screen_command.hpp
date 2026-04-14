#pragma once

#include <string>

#include "../agent_state.hpp"

namespace command
{

struct LockScreenExecutionResult
{
  bool success{false};
  int error_code{0};
  std::string reason;
  std::string notes;
  std::string data_json;
  std::string output_text;
  std::string meta_json;
};

bool IsLockScreenMethod(const std::string &method);

LockScreenExecutionResult ExecuteLockScreenCommand(
    const AgentState &state,
    const std::string &command_message_id,
    const std::string &params_json);

} // namespace command

