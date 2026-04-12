#pragma once

#include <string>

#include "../agent_state.hpp"
#include "../config/config.hpp"

namespace command
{

struct ScreenshotExecutionResult
{
  bool success{false};
  int error_code{0};
  std::string reason;
  std::string notes;
  std::string artifact_url;
  std::string artifact_checksum;
  std::string data_json;
  std::string output_text;
  std::string meta_json;
};

bool IsScreenshotMethod(const std::string &method);

ScreenshotExecutionResult ExecuteScreenshotCommand(
    const AgentConfig &config,
    const AgentState &state,
    const std::string &command_message_id,
    const std::string &params_json);

} // namespace command
