#include "ed25519_sign.hpp"
#include <sstream>
#include <functional>
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

std::string ed25519_sign_payload(const std::string &payload)
{
#ifdef HAVE_SODIUM
    if (sodium_init() < 0)
    {
        std::cerr << "ed25519_sign: sodium_init failed\n";
        return {};
    }

    const char *b64 = std::getenv("ED25519_PRIVATE_KEY_B64");
    std::string skfile;
#ifdef _WIN32
    if (!b64)
    {
        std::string dpapi_b64;
        if (dpapi_load_blob_to_b64("ED25519_PRIVATE_KEY_DPAPI_B64", "ED25519_PRIVATE_KEY_DPAPI_PATH", dpapi_b64))
        {
            skfile = dpapi_b64;
            b64 = skfile.c_str();
        }
    }
#endif
    if (!b64)
    {
        std::cerr << "ed25519_sign: ED25519_PRIVATE_KEY_B64 not set\n";
        return {};
    }

    std::vector<unsigned char> sk(64);
    size_t bin_len = 0;
    if (sodium_base642bin(sk.data(), sk.size(), b64, strlen(b64), NULL, &bin_len, NULL, sodium_base64_VARIANT_ORIGINAL) != 0)
    {
        std::cerr << "ed25519_sign: failed to decode base64 private key\n";
        return {};
    }
    if (bin_len != 64)
    {
        std::cerr << "ed25519_sign: unexpected private key length\n";
        return {};
    }

    unsigned char sig[crypto_sign_BYTES];
    if (crypto_sign_detached(sig, NULL, reinterpret_cast<const unsigned char *>(payload.data()), payload.size(), sk.data()) != 0)
    {
        std::cerr << "ed25519_sign: crypto_sign_detached failed\n";
        return {};
    }

    char out[crypto_sign_BYTES * 2 + 16];
    sodium_bin2base64(out, sizeof(out), sig, crypto_sign_BYTES, sodium_base64_VARIANT_ORIGINAL);
    return std::string(out);
#else
    // Fallback (non-crypto) deterministic signature used in dev/test.
    std::hash<std::string> hasher;
    std::ostringstream oss;
    oss << std::hex << hasher(payload);
    return oss.str();
#endif
}
