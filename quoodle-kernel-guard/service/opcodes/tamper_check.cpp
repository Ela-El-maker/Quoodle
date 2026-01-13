#include <string>
#include <fstream>
#include <sstream>
#include <filesystem>
#include <functional>
#include "../utils/logger.hpp"

namespace fs = std::filesystem;

// Simple rolling hash over file (doesn't load entire file into memory)
static uint64_t simple_file_hash(const fs::path &path)
{
  std::ifstream f(path, std::ios::binary | std::ios::ate);
  if (!f)
    return 0;

  auto size = f.tellg();
  f.seekg(0);

  uint64_t hash = 5381; // djb2 initial value
  char buf[4096];
  while (f.read(buf, sizeof(buf)))
  {
    for (size_t i = 0; i < f.gcount(); ++i)
      hash = ((hash << 5) + hash) + static_cast<unsigned char>(buf[i]);
  }
  return hash;
}

// Dev-mode baseline (in production, this would be signed/verified against policy)
static constexpr uint64_t EXPECTED_HASH = 0xDEADBEEF12345678ULL; // replace with real hash

bool execute_tamper_check()
{
  try
  {
    fs::path path = fs::current_path() / "kernel_service";
    if (!fs::exists(path))
    {
      utils::log_error("tamper_check: kernel_service binary missing");
      return false;
    }

    uint64_t actual_hash = simple_file_hash(path);
    utils::log_info("tamper_check: computed hash=0x" +
                    std::string(reinterpret_cast<const char *>(&actual_hash), sizeof(actual_hash)));

    if (actual_hash != EXPECTED_HASH)
    {
      utils::log_error("tamper_check: hash mismatch! expected=0x" +
                       std::string(reinterpret_cast<const char *>(&EXPECTED_HASH), sizeof(EXPECTED_HASH)) +
                       " actual=0x" + std::string(reinterpret_cast<const char *>(&actual_hash), sizeof(actual_hash)));
      return false;
    }

    utils::log_info("tamper_check: binary verified OK");
    return true;
  }
  catch (const std::exception &e)
  {
    utils::log_error("tamper_check: exception: " + std::string(e.what()));
    return false;
  }
}
