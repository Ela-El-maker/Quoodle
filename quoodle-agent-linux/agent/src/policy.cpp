#include "policy.h"

#include <cstdlib>
#include <fstream>
#include <sodium.h>

namespace quoodle {

namespace {

std::string ReadTrimmedFile(const char *path) {
    if (!path || !*path) {
        return {};
    }

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

std::string ResolveHardwareIdentity() {
    if (const char *hwid = std::getenv("QUOODLE_HWID"); hwid && *hwid) {
        return hwid;
    }
    if (const char *path = std::getenv("QUOODLE_HWID_FILE"); path && *path) {
        auto value = ReadTrimmedFile(path);
        if (!value.empty()) {
            return value;
        }
    }

    auto persisted = ReadTrimmedFile("/var/lib/quoodle/hwid");
    if (!persisted.empty()) {
        return persisted;
    }

    if (const char *device_id = std::getenv("QUOODLE_DEVICE_ID"); device_id && *device_id) {
        return device_id;
    }
    if (const char *path = std::getenv("QUOODLE_DEVICE_ID_FILE"); path && *path) {
        auto value = ReadTrimmedFile(path);
        if (!value.empty()) {
            return value;
        }
    }

    return ReadTrimmedFile("/var/lib/quoodle/device_id");
}

std::string HexEncode(const unsigned char *data, size_t len) {
    static constexpr char kHex[] = "0123456789abcdef";
    std::string out;
    out.reserve(len * 2);
    for (size_t i = 0; i < len; ++i) {
        out.push_back(kHex[(data[i] >> 4) & 0x0F]);
        out.push_back(kHex[data[i] & 0x0F]);
    }
    return out;
}

}  // namespace

void PolicyState::Apply(const std::unordered_map<std::string, std::string> &policy_fields) {
    auto it_hash = policy_fields.find("policy_hash");
    if (it_hash != policy_fields.end()) {
        policy_hash_ = it_hash->second;
    }
    auto it_version = policy_fields.find("policy_version");
    if (it_version != policy_fields.end()) {
        policy_version_ = it_version->second;
    }
}

void PolicyState::SetPolicyHash(const std::string &policy_hash) {
    policy_hash_ = policy_hash;
}

std::unordered_map<std::string, std::string> PolicyState::AgentInfo() const {
    return {
        {"agent_version", "0.1.0-linux"},
        {"os_build", "linux"},
    };
}

std::string PolicyState::HwidHash() const {
    const auto identity = ResolveHardwareIdentity();
    if (identity.empty()) {
        return {};
    }

    if (sodium_init() < 0) {
        return {};
    }

    unsigned char digest[crypto_hash_sha256_BYTES];
    crypto_hash_sha256(
        digest,
        reinterpret_cast<const unsigned char *>(identity.data()),
        identity.size());
    return "sha256:" + HexEncode(digest, sizeof(digest));
}

std::string PolicyState::PolicyHash() const {
    return policy_hash_;
}

}  // namespace quoodle
