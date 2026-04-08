#include "ed25519_sign.hpp"
#include <cstdlib>
#include <iostream>
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
bool load_private_key_from_env_or_dpapi(std::vector<unsigned char> &sk)
{
    const char *b64 = std::getenv("ED25519_PRIVATE_KEY_B64");
    std::string dpapi_b64;
#ifdef _WIN32
    if (!b64)
    {
        if (dpapi_load_blob_to_b64("ED25519_PRIVATE_KEY_DPAPI_B64", "ED25519_PRIVATE_KEY_DPAPI_PATH", dpapi_b64))
        {
            b64 = dpapi_b64.c_str();
        }
    }
#endif
    if (!b64)
    {
        std::cerr << "ed25519_sign: ED25519_PRIVATE_KEY_B64 not set\n";
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
