#pragma once

#include <string>

#include "../agent_state.hpp"

namespace command
{

struct ObservabilityExecutionResult
{
  bool success{false};
  int error_code{0};
  std::string reason;
  std::string notes;
  std::string data_json;
  std::string output_text;
  std::string meta_json;
};

bool IsObservabilityMethod(const std::string &method);

ObservabilityExecutionResult ExecuteObservabilityCommand(
    const AgentState &state,
    const std::string &method,
    const std::string &command_message_id,
    const std::string &params_json);

} // namespace command

