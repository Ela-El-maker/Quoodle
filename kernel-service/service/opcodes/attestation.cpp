// attestation.cpp
#include <string>
#include <unordered_map>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>
#include "../utils/logger.hpp"

namespace fs = std::filesystem;

// Simple streaming SHA256 placeholder (use OpenSSL or Windows CryptoAPI in prod)
static std::string simple_sha256(const fs::path &path)
{
  // TODO: replace with real SHA256
  std::ifstream f(path, std::ios::binary | std::ios::ate);
  if (!f)
    return "sha256:missing";

  auto size = f.tellg();
  f.seekg(0);

  std::ostringstream oss;
  oss << "sha256:" << std::hex << std::setw(16) << std::setfill('0') << size;
  return oss.str();
}

std::unordered_map<std::string, std::string> execute_attestation()
{
  utils::log_info("attestation: running attestation checks");

  std::unordered_map<std::string, std::string> result;

  // Agent binary hash
  result["agent_hash"] = simple_sha256(fs::current_path() / "agent.exe");

  // KernelService binary hash
  result["kernelservice_hash"] = simple_sha256(fs::current_path() / "kernel_service");

  // TPM quote (stub - requires TPM2 libraries in production)
  result["tpm_quote"] = "base64:tpm-quote-stub-" +
                        simple_sha256(fs::current_path() / "kernel_service").substr(7);

  utils::log_info("attestation: complete (agent=" + result.at("agent_hash").substr(0, 16) +
                  ", kernel=" + result.at("kernelservice_hash").substr(0, 16) + ")");

  return result;
}
