#include "validate_update_package.hpp"

#include <windows.h>
#include <bcrypt.h>
#include <filesystem>
#include <fstream>
#include <vector>
#include <iomanip>
#include <sstream>

#include "../utils/logger.hpp"

#pragma comment(lib, "bcrypt.lib")

namespace fs = std::filesystem;

// =======================================================
// Compute SHA256 using Windows CNG (BCrypt)
// =======================================================
static std::string compute_sha256_hex(const fs::path &file_path)
{
  BCRYPT_ALG_HANDLE hAlg = nullptr;
  BCRYPT_HASH_HANDLE hHash = nullptr;
  NTSTATUS status;

  DWORD hashObjectSize = 0;
  DWORD hashLen = 0;
  DWORD cbData = 0;

  std::vector<BYTE> hashObject;
  std::vector<BYTE> hash;

  // Open SHA256 provider
  status = BCryptOpenAlgorithmProvider(
      &hAlg,
      BCRYPT_SHA256_ALGORITHM,
      nullptr,
      0);

  if (!BCRYPT_SUCCESS(status))
    return "";

  // Get hash object size
  status = BCryptGetProperty(
      hAlg,
      BCRYPT_OBJECT_LENGTH,
      reinterpret_cast<PUCHAR>(&hashObjectSize),
      sizeof(DWORD),
      &cbData,
      0);

  if (!BCRYPT_SUCCESS(status))
    goto cleanup;

  // Get hash length
  status = BCryptGetProperty(
      hAlg,
      BCRYPT_HASH_LENGTH,
      reinterpret_cast<PUCHAR>(&hashLen),
      sizeof(DWORD),
      &cbData,
      0);

  if (!BCRYPT_SUCCESS(status))
    goto cleanup;

  hashObject.resize(hashObjectSize);
  hash.resize(hashLen);

  // Create hash
  status = BCryptCreateHash(
      hAlg,
      &hHash,
      hashObject.data(),
      hashObjectSize,
      nullptr,
      0,
      0);

  if (!BCRYPT_SUCCESS(status))
    goto cleanup;

  // Read file and hash
  std::ifstream file(file_path, std::ios::binary);
  if (!file)
    goto cleanup;

  char buffer[8192];
  while (file.read(buffer, sizeof(buffer)) || file.gcount() > 0)
  {
    ULONG bytesRead = static_cast<ULONG>(file.gcount());
    if (bytesRead == 0)
      break;

    status = BCryptHashData(
        hHash,
        reinterpret_cast<PUCHAR>(buffer),
        bytesRead,
        0);

    if (!BCRYPT_SUCCESS(status))
      goto cleanup;
  }

  // Finalize hash
  status = BCryptFinishHash(
      hHash,
      hash.data(),
      hashLen,
      0);

  if (!BCRYPT_SUCCESS(status))
    goto cleanup;

  // Convert to hex string
  std::ostringstream oss;
  oss << std::hex << std::setfill('0');
  for (BYTE b : hash)
    oss << std::setw(2) << static_cast<int>(b);

cleanup:
  if (hHash)
    BCryptDestroyHash(hHash);
  if (hAlg)
    BCryptCloseAlgorithmProvider(hAlg, 0);

  return BCRYPT_SUCCESS(status) ? oss.str() : "";
}

// =======================================================
// Validate update package
// =======================================================
bool execute_validate_update_package(const std::string &path_str)
{
  utils::log_info("validate_update_package: checking " + path_str);

  try
  {
    fs::path pkg = fs::weakly_canonical(fs::path(path_str));

    // 1. File existence and type
    if (!fs::exists(pkg) || !fs::is_regular_file(pkg))
    {
      utils::log_error("validate_update_package: invalid file: " + pkg.string());
      return false;
    }

    // 2. File size sanity (0 < size ≤ 100MB)
    constexpr uintmax_t MAX_SIZE = 100 * 1024 * 1024;
    uintmax_t size = fs::file_size(pkg);

    if (size == 0 || size > MAX_SIZE)
    {
      utils::log_error(
          "validate_update_package: invalid file size: " +
          std::to_string(size));
      return false;
    }

    // 3. Compute SHA256
    std::string actual_hash = compute_sha256_hex(pkg);
    if (actual_hash.empty())
    {
      utils::log_error("validate_update_package: SHA256 computation failed");
      return false;
    }

    // NOTE:
    // In production, expected_hash should come from a SIGNED MANIFEST,
    // not be hardcoded.
    const std::string expected_hash = "REPLACE_WITH_REAL_HASH";

    if (actual_hash != expected_hash)
    {
      utils::log_error(
          "validate_update_package: hash mismatch "
          "(expected=" +
          expected_hash +
          ", actual=" + actual_hash + ")");
      return false;
    }

    // 4. Signature presence check (verification hook)
    fs::path sig_path = pkg;
    sig_path += ".sig";

    if (!fs::exists(sig_path))
    {
      utils::log_error("validate_update_package: missing signature file: " +
                       sig_path.string());
      return false;
    }

    // TODO:
    // Verify detached signature:
    // - Load public key
    // - Verify signature against pkg hash
    // - Fail if verification fails

    utils::log_info("validate_update_package: SUCCESS (" + actual_hash + ")");
    return true;
  }
  catch (const std::exception &e)
  {
    utils::log_error(
        "validate_update_package: exception: " +
        std::string(e.what()));
    return false;
  }
}
