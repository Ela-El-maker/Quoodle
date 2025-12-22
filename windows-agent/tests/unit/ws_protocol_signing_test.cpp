#include <cassert>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "ws/ws_protocol.hpp"
#include "ws/sequence_manager.hpp"

#ifdef HAVE_SODIUM
#include <sodium.h>
#endif

static void set_env(const char *key, const std::string &value)
{
#ifdef _WIN32
    _putenv_s(key, value.c_str());
#else
    setenv(key, value.c_str(), 1);
#endif
}

static std::vector<unsigned char> b64decode(const std::string &b64)
{
#ifdef HAVE_SODIUM
    std::vector<unsigned char> out(b64.size());
    size_t out_len = 0;
    if (sodium_base642bin(out.data(), out.size(), b64.c_str(), b64.size(), NULL, &out_len, NULL, sodium_base64_VARIANT_ORIGINAL) != 0)
    {
        return {};
    }
    out.resize(out_len);
    return out;
#else
    (void)b64;
    return {};
#endif
}

static std::string b64encode(const unsigned char *data, size_t len)
{
#ifdef HAVE_SODIUM
    std::string out;
    out.resize(len * 2 + 16);
    sodium_bin2base64(out.data(), out.size(), data, len, sodium_base64_VARIANT_ORIGINAL);
    out.resize(std::strlen(out.c_str()));
    return out;
#else
    (void)data;
    (void)len;
    return {};
#endif
}

static bool verify_sig_detached(const nlohmann::json &msg, const unsigned char *pk)
{
#ifdef HAVE_SODIUM
    if (!msg.contains("sig"))
        return false;

    const std::string sig_b64 = msg.at("sig").get<std::string>();
    auto sig = b64decode(sig_b64);
    if (sig.size() != crypto_sign_BYTES)
        return false;

    nlohmann::json unsigned_msg = msg;
    unsigned_msg.erase("sig");

    // Canonicalize with sorted keys (recursively), compact separators.
    std::function<nlohmann::json(const nlohmann::json &)> sort_keys;
    sort_keys = [&](const nlohmann::json &j) -> nlohmann::json
    {
        if (j.is_object())
        {
            std::vector<std::string> keys;
            keys.reserve(j.size());
            for (auto it = j.begin(); it != j.end(); ++it)
            {
                keys.push_back(it.key());
            }
            std::sort(keys.begin(), keys.end());
            nlohmann::json out = nlohmann::json::object();
            for (const auto &k : keys)
            {
                out[k] = sort_keys(j.at(k));
            }
            return out;
        }
        if (j.is_array())
        {
            nlohmann::json out = nlohmann::json::array();
            for (const auto &el : j)
            {
                out.push_back(sort_keys(el));
            }
            return out;
        }
        return j;
    };

    const std::string payload = sort_keys(unsigned_msg).dump(-1, ' ', false, nlohmann::json::error_handler_t::strict);

    return crypto_sign_verify_detached(sig.data(), reinterpret_cast<const unsigned char *>(payload.data()), payload.size(), pk) == 0;
#else
    (void)msg;
    (void)pk;
    return true; // can't verify without libsodium
#endif
}

int main()
{
#ifdef HAVE_SODIUM
    if (sodium_init() < 0)
    {
        std::cerr << "sodium_init failed\n";
        return 1;
    }

    unsigned char pk[crypto_sign_PUBLICKEYBYTES];
    unsigned char sk[crypto_sign_SECRETKEYBYTES];
    crypto_sign_keypair(pk, sk);

    set_env("ED25519_PRIVATE_KEY_B64", b64encode(sk, sizeof(sk)));

    const auto seq_path = (std::filesystem::temp_directory_path() / "system002_agent_seq_test.txt").string();
    set_env("AGENT_SEQ_PATH", seq_path);

    // Verify SequenceManager persistence behavior directly.
    {
        SequenceManager mgr(seq_path);
        const auto a = mgr.next();
        const auto b = mgr.next();
        assert(b > a);
    }
    {
        SequenceManager mgr(seq_path);
        const auto c = mgr.next();
        assert(c >= 3);
    }

    // Verify that protocol builders emit seq and a valid Ed25519 signature.
    const auto auth_env = build_auth_envelope("PC_TEST", "dummy.jwt");
    const auto auth_json_str = build_signed_auth_json(auth_env);
    const auto auth_msg = nlohmann::json::parse(auth_json_str);

    assert(auth_msg.at("type").get<std::string>() == "AUTH");
    assert(auth_msg.contains("seq"));
    assert(auth_msg.at("seq").get<std::uint64_t>() >= 1);
    assert(verify_sig_detached(auth_msg, pk));

    const auto hb_json_str = build_signed_heartbeat_json("PC_TEST", "sess-1");
    const auto hb_msg = nlohmann::json::parse(hb_json_str);

    assert(hb_msg.at("type").get<std::string>() == "HEARTBEAT");
    assert(hb_msg.at("seq").get<std::uint64_t>() > auth_msg.at("seq").get<std::uint64_t>());
    assert(verify_sig_detached(hb_msg, pk));

    const auto ack_json_str = build_command_ack_json("PC_TEST", "sess-1", "cmd-123");
    const auto ack_msg = nlohmann::json::parse(ack_json_str);

    assert(ack_msg.at("type").get<std::string>() == "COMMAND_ACK");
    assert(ack_msg.at("seq").get<std::uint64_t>() > hb_msg.at("seq").get<std::uint64_t>());
    assert(verify_sig_detached(ack_msg, pk));

    std::cout << "ws_protocol_signing_test passed\n";
    return 0;
#else
    std::cout << "ws_protocol_signing_test skipped (HAVE_SODIUM=0)\n";
    return 0;
#endif
}
