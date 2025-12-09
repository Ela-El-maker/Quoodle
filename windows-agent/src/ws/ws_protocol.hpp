#pragma once

#include <string>

struct AgentInfo {
    std::string agent_version{"0.0.1"};
    std::string attestation_hash{"sha256:placeholder"};
    std::string hwid_hash{"sha256:placeholder-hwid"};
    std::string os_build{"19045"};
};

struct AuthBody {
    std::string jwt;
    std::string nonce;
    AgentInfo agent_info{};
};

struct AuthEnvelope {
    std::string type{"AUTH"};
    std::string from{"agent"};
    std::string device_id{"PC001"};
    std::string message_id;
    std::string session_id{"null"};
    std::string timestamp;
    AuthBody body{};
    std::string sig;
};

AuthEnvelope build_auth_envelope(const std::string& device_id, const std::string& jwt_token);

std::string canonical_auth_without_sig(const AuthEnvelope& envelope);

std::string sign_placeholder(const std::string& canonical_json);

std::string build_signed_auth_json(AuthEnvelope envelope);
