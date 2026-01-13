#include <string>
#include <chrono>
#include <sstream>
#include "../utils/logger.hpp"

std::string execute_ping()
{
  using clock = std::chrono::system_clock;
  auto now = clock::now();

  auto secs = std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch()).count();

  // Log a structured health event
  utils::log_info("ping: healthcheck ok");

  std::ostringstream oss;

  oss << R"({"status":"ok","reply":"pong","ts":)" << secs << "}";

  return oss.str();
}
