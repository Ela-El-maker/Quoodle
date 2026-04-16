#include "ed25519_sign.hpp"
#include <cstdlib>
#include <cctype>
#include <iostream>
#include <fstream>
#include <filesystem>
#include <exception>
#ifdef HAVE_SODIUM
#include <sodium.h>
#include <vector>
#include <cstring>
#endif
#ifdef _WIN32
#include "../utils/dpapi_loader.hpp"
#endif

#ifdef HAVE_SODIUM
namespace
{
bool parse_bool_env(const char *name, bool default_value)
{
    const char *raw = std::getenv(name);
    if (!raw || !*raw)
    {
        return default_value;
    }

    std::string value(raw);
    for (char &ch : value)
    {
        ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    }
    if (value == "1" || value == "true" || value == "yes" || value == "on")
    {
        return true;
    }
    if (value == "0" || value == "false" || value == "no" || value == "off")
    {
        return false;
    }
    return default_value;
}

std::string read_file_trimmed(const std::filesystem::path &path)
{
    std::ifstream in(path);
    if (!in)
    {
        return {};
    }

    std::string value;
    std::getline(in, value);
    while (!value.empty() && (value.back() == '\r' || value.back() == '\n' || value.back() == ' ' || value.back() == '\t'))
    {
        value.pop_back();
    }
    return value;
}

std::filesystem::path default_private_key_path()
{
    const char *env_path = std::getenv("ED25519_PRIVATE_KEY_PATH");
    if (env_path && *env_path)
    {
        return std::filesystem::path(env_path);
    }
    return std::filesystem::path("C:/ProgramData/Quoodle/ed25519_private_key.b64");
}

bool has_agent_jwt()
{
    const char *jwt_env = std::getenv("AGENT_JWT");
    if (jwt_env && *jwt_env)
    {
        return true;
    }

    const char *jwt_file_env = std::getenv("AGENT_JWT_FILE");
    const std::filesystem::path jwt_path = (jwt_file_env && *jwt_file_env)
                                               ? std::filesystem::path(jwt_file_env)
                                               : std::filesystem::path("C:/ProgramData/Quoodle/agent_jwt");
    return !read_file_trimmed(jwt_path).empty();
}

bool try_generate_private_key_file(const std::filesystem::path &path, std::string &b64_out)
{
    unsigned char pk[crypto_sign_PUBLICKEYBYTES];
    unsigned char sk[crypto_sign_SECRETKEYBYTES];
    if (crypto_sign_keypair(pk, sk) != 0)
    {
        std::cerr << "ed25519_sign: keypair generation failed\n";
        return false;
    }

    char sk_b64[crypto_sign_SECRETKEYBYTES * 2 + 16];
    sodium_bin2base64(sk_b64, sizeof(sk_b64), sk, crypto_sign_SECRETKEYBYTES, sodium_base64_VARIANT_ORIGINAL);
    b64_out = sk_b64;

    try
    {
        const auto parent = path.parent_path();
        if (!parent.empty())
        {
            std::filesystem::create_directories(parent);
        }

        std::ofstream out(path, std::ios::trunc);
        if (!out)
        {
            sodium_memzero(sk, sizeof(sk));
            std::cerr << "ed25519_sign: unable to persist generated key to " << path.string() << "\n";
            return false;
        }
        out << b64_out << "\n";
    }
    catch (const std::exception &ex)
    {
        sodium_memzero(sk, sizeof(sk));
        std::cerr << "ed25519_sign: key persistence error: " << ex.what() << "\n";
        return false;
    }

    sodium_memzero(sk, sizeof(sk));
    return true;
}

bool load_private_key_from_env_or_dpapi(std::vector<unsigned char> &sk)
{
    // Prefer persisted key material first so paired identity remains stable
    // even when machine/user environment variables are stale.
    const bool env_first = parse_bool_env("ED25519_ENV_PRIORITY", false);
    const auto key_path = default_private_key_path();

    std::string env_b64;
    if (const char *env = std::getenv("ED25519_PRIVATE_KEY_B64"))
    {
        if (*env)
        {
            env_b64 = env;
        }
    }

    std::string dpapi_b64;
#ifdef _WIN32
    if (dpapi_load_blob_to_b64("ED25519_PRIVATE_KEY_DPAPI_B64", "ED25519_PRIVATE_KEY_DPAPI_PATH", dpapi_b64))
    {
        // Keep value in dpapi_b64 for lifetime; selected below.
    }
#endif

    std::string file_b64 = read_file_trimmed(key_path);
    if (file_b64.empty())
    {
        const bool allow_autogen = parse_bool_env("ED25519_AUTOGEN_PRIVATE_KEY", true);
        if (allow_autogen && !has_agent_jwt())
        {
            if (try_generate_private_key_file(key_path, file_b64))
            {
                std::cerr << "ed25519_sign: generated local Ed25519 key at " << key_path.string() << "\n";
            }
        }
    }

    const char *b64 = nullptr;
    if (env_first)
    {
        if (!env_b64.empty())
        {
            b64 = env_b64.c_str();
        }
        else if (!dpapi_b64.empty())
        {
            b64 = dpapi_b64.c_str();
        }
        else if (!file_b64.empty())
        {
            b64 = file_b64.c_str();
        }
    }
    else
    {
        if (!file_b64.empty() && !env_b64.empty() && file_b64 != env_b64)
        {
            std::cerr << "ed25519_sign: using persisted key file over ED25519_PRIVATE_KEY_B64 env override\n";
        }
        if (!file_b64.empty())
        {
            b64 = file_b64.c_str();
        }
        else if (!dpapi_b64.empty())
        {
            b64 = dpapi_b64.c_str();
        }
        else if (!env_b64.empty())
        {
            b64 = env_b64.c_str();
        }
    }

    if (!b64)
    {
        std::cerr << "ed25519_sign: private key not set (env/dpapi/file) and autogen unavailable\n";
        return false;
    }

    sk.assign(64, 0);
    size_t bin_len = 0;
    if (sodium_base642bin(sk.data(), sk.size(), b64, std::strlen(b64), NULL, &bin_len, NULL, sodium_base64_VARIANT_ORIGINAL) != 0)
    {
        std::cerr << "ed25519_sign: failed to decode base64 private key\n";
        return false;
    }
    if (bin_len != 64)
    {
        std::cerr << "ed25519_sign: unexpected private key length\n";
        return false;
    }
    return true;
}
} // namespace
#endif

std::string ed25519_sign_payload(const std::string &payload)
{
#ifdef HAVE_SODIUM
    if (sodium_init() < 0)
    {
        std::cerr << "ed25519_sign: sodium_init failed\n";
        return {};
    }

    std::vector<unsigned char> sk;
    if (!load_private_key_from_env_or_dpapi(sk))
    {
        return {};
    }

    unsigned char sig[crypto_sign_BYTES];
    if (crypto_sign_detached(sig, NULL, reinterpret_cast<const unsigned char *>(payload.data()), payload.size(), sk.data()) != 0)
    {
        sodium_memzero(sk.data(), sk.size()); // Clear secret key on error
        std::cerr << "ed25519_sign: crypto_sign_detached failed\n";
        return {};
    }

    // Clear secret key from memory immediately after use
    sodium_memzero(sk.data(), sk.size());

    char out[crypto_sign_BYTES * 2 + 16];
    sodium_bin2base64(out, sizeof(out), sig, crypto_sign_BYTES, sodium_base64_VARIANT_ORIGINAL);
    return std::string(out);
#else
    (void)payload;
    std::cerr << "ed25519_sign: libsodium not available\n";
    return {};
#endif
}

std::string ed25519_active_public_key_b64()
{
#ifdef HAVE_SODIUM
    if (sodium_init() < 0)
    {
        std::cerr << "ed25519_sign: sodium_init failed\n";
        return {};
    }

    std::vector<unsigned char> sk;
    if (!load_private_key_from_env_or_dpapi(sk))
    {
        return {};
    }

    unsigned char pk[crypto_sign_PUBLICKEYBYTES];
    if (crypto_sign_ed25519_sk_to_pk(pk, sk.data()) != 0)
    {
        sodium_memzero(sk.data(), sk.size());
        std::cerr << "ed25519_sign: failed to derive public key from private key\n";
        return {};
    }

    sodium_memzero(sk.data(), sk.size());

    char out[crypto_sign_PUBLICKEYBYTES * 2 + 16];
    sodium_bin2base64(out, sizeof(out), pk, crypto_sign_PUBLICKEYBYTES, sodium_base64_VARIANT_ORIGINAL);
    return std::string(out);
#else
    return {};
#endif
}
