#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

#include "outbox.h"
#include "policy.h"
#include "privileged_client.h"
#include "replay.h"
#include "state_store.h"
#include "wss_client.h"

namespace {

std::string GetEnvOrThrow(const char *name) {
    const char *value = std::getenv(name);
    if (!value || !*value) {
        throw std::runtime_error(std::string("Missing required env var: ") + name);
    }
    return value;
}

std::string ReadFileTrim(const std::filesystem::path &path) {
    std::ifstream file(path);
    if (!file) {
        return {};
    }
    std::string value;
    std::getline(file, value);
    while (!value.empty() && (value.back() == '\n' || value.back() == '\r' || value.back() == ' ' || value.back() == '\t')) {
        value.pop_back();
    }
    return value;
}

std::string ReadUuidFromKernel() {
    return ReadFileTrim("/proc/sys/kernel/random/uuid");
}

std::string GetOrCreateIdentity(const char *env_name, const char *file_env_name, const std::filesystem::path &default_path) {
    const char *env_value = std::getenv(env_name);
    if (env_value && *env_value) {
        return env_value;
    }
    const char *path_env = std::getenv(file_env_name);
    std::filesystem::path path = (path_env && *path_env) ? std::filesystem::path(path_env) : default_path;
    auto existing = ReadFileTrim(path);
    if (!existing.empty()) {
        return existing;
    }
    std::string generated = ReadUuidFromKernel();
    if (generated.empty()) {
        throw std::runtime_error(std::string("Unable to generate identity for ") + env_name);
    }
    std::filesystem::create_directories(path.parent_path());
    std::ofstream out(path, std::ios::trunc);
    if (!out) {
        throw std::runtime_error(std::string("Unable to write identity file: ") + path.string());
    }
    out << generated << "\n";
    return generated;
}

}  // namespace

int main() {
    try {
        auto ws_url = GetEnvOrThrow("QUOODLE_WS_URL");
        auto device_id = GetOrCreateIdentity("QUOODLE_DEVICE_ID", "QUOODLE_DEVICE_ID_FILE", "/var/lib/quoodle/device_id");
        (void) GetOrCreateIdentity("QUOODLE_HWID", "QUOODLE_HWID_FILE", "/var/lib/quoodle/hwid");
        auto agent_jwt = GetEnvOrThrow("QUOODLE_AGENT_JWT");
        auto agent_kid = GetEnvOrThrow("QUOODLE_AGENT_KID");
        auto agent_priv_b64 = GetEnvOrThrow("QUOODLE_AGENT_PRIVKEY_B64");

        quoodle::AgentStateStore state;
        state.Load();

        quoodle::PolicyState policy;
        if (!state.PolicyHash().empty()) {
            policy.SetPolicyHash(state.PolicyHash());
        }

        quoodle::Outbox outbox;
        outbox.Load();

        quoodle::ReplayCache replay(state);
        replay.Load();

        quoodle::PrivilegedClient privileged(replay);
        quoodle::CommandProcessor processor(outbox, privileged, state);

        quoodle::WssClient client(
            ws_url, device_id, agent_jwt, agent_kid, agent_priv_b64, policy, outbox, replay, state, processor);
        client.Run();
        return 0;
    } catch (const std::exception &ex) {
        std::cerr << "Agent startup failed: " << ex.what() << "\n";
        return 1;
    }
}
