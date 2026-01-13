#include <string>
#include <filesystem>
#include <fstream>
#include <random>
#include <sstream>
#include "../utils/logger.hpp"

namespace fs = std::filesystem;

static std::string generate_sandbox_id()
{
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<uint64_t> dis;
    std::ostringstream oss;
    oss << "sandbox-" << std::hex << dis(gen);
    return oss.str();
}

std::string execute_stage_update(const std::string &package_path, bool sandbox)
{
  try
  {
    fs::path pkg(package_path);
    if (!fs::exists(pkg))
    {
      utils::log_error("stage_update: package not found: " + package_path);
      return {};
    }

    // e.g. <cwd>/stage/sandbox or <cwd>/stage/direct
    fs::path base_stage = fs::current_path() / "stage" / (sandbox ? "sandbox" : "direct");
    fs::create_directories(base_stage);

    std::string sandbox_id = generate_sandbox_id();
    fs::path dest = base_stage / (sandbox_id + pkg.extension().string());

    fs::copy_file(pkg, dest, fs::copy_options::overwrite_existing);

    utils::log_info("stage_update: staged package to " + dest.string() +
                    " (sandbox_id=" + sandbox_id + ")");

    return sandbox_id;
  }
    catch (const std::exception &e)
    {
        utils::log_error(std::string("stage_update: exception: ") + e.what());
        return {};
    }
}
