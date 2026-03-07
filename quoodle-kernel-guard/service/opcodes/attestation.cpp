// attestation.cpp
#include <string>
#include <unordered_map>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <vector>

#include <windows.h>
#include <bcrypt.h>

#include "../utils/logger.hpp"

#pragma comment(lib, "bcrypt.lib")

namespace fs = std::filesystem;

// Compute SHA256 of a file using Windows CNG (BCrypt)
static std::string compute_sha256(const fs::path &path)
{
  BCRYPT_ALG_HANDLE hAlg = nullptr;
  BCRYPT_HASH_HANDLE hHash = nullptr;
  NTSTATUS status;

  DWORD hashObjectSize = 0, hashLen = 0, cbData = 0;
  std::vector<BYTE> hashObject, hash;

  status = BCryptOpenAlgorithmProvider(&hAlg, BCRYPT_SHA256_ALGORITHM, nullptr, 0);
  if (!BCRYPT_SUCCESS(status))
    return "sha256:error";

  status = BCryptGetProperty(hAlg, BCRYPT_OBJECT_LENGTH,
                             reinterpret_cast<PUCHAR>(&hashObjectSize), sizeof(DWORD), &cbData, 0);
  if (!BCRYPT_SUCCESS(status))
  {
    BCryptCloseAlgorithmProvider(hAlg, 0);
    return "sha256:error";
  }

  status = BCryptGetProperty(hAlg, BCRYPT_HASH_LENGTH,
                             reinterpret_cast<PUCHAR>(&hashLen), sizeof(DWORD), &cbData, 0);
  if (!BCRYPT_SUCCESS(status))
  {
    BCryptCloseAlgorithmProvider(hAlg, 0);
    return "sha256:error";
  }

  hashObject.resize(hashObjectSize);
  hash.resize(hashLen);

  status = BCryptCreateHash(hAlg, &hHash, hashObject.data(), hashObjectSize, nullptr, 0, 0);
  if (!BCRYPT_SUCCESS(status))
  {
    BCryptCloseAlgorithmProvider(hAlg, 0);
    return "sha256:error";
  }

  std::ifstream file(path, std::ios::binary);
  if (!file)
  {
    BCryptDestroyHash(hHash);
    BCryptCloseAlgorithmProvider(hAlg, 0);
    return "sha256:missing";
  }

  char buffer[8192];
  while (file.read(buffer, sizeof(buffer)) || file.gcount() > 0)
  {
    ULONG bytesRead = static_cast<ULONG>(file.gcount());
    if (bytesRead == 0)
      break;
    status = BCryptHashData(hHash, reinterpret_cast<PUCHAR>(buffer), bytesRead, 0);
    if (!BCRYPT_SUCCESS(status))
      break;
  }

  if (BCRYPT_SUCCESS(status))
    status = BCryptFinishHash(hHash, hash.data(), hashLen, 0);

  BCryptDestroyHash(hHash);
  BCryptCloseAlgorithmProvider(hAlg, 0);

  if (!BCRYPT_SUCCESS(status))
    return "sha256:error";

  std::ostringstream oss;
  oss << "sha256:" << std::hex << std::setfill('0');
  for (BYTE b : hash)
    oss << std::setw(2) << static_cast<int>(b);
  return oss.str();
}

std::unordered_map<std::string, std::string> execute_attestation()
{
  utils::log_info("attestation: running attestation checks");

  std::unordered_map<std::string, std::string> result;

  // Agent binary hash
  result["agent_hash"] = compute_sha256(fs::current_path() / "agent.exe");

  // KernelService binary hash
  result["kernelservice_hash"] = compute_sha256(fs::current_path() / "kernel_service");

  // TPM quote requires platform-specific TPM2 libraries (tbs.h / Tbsi_Context_Create)
  // Report honestly that TPM attestation is not yet available
  result["tpm_quote"] = "unsupported:tpm-not-implemented";

  utils::log_info("attestation: complete (agent=" + result.at("agent_hash").substr(0, 16) +
                  ", kernel=" + result.at("kernelservice_hash").substr(0, 16) + ")");

  return result;
}
