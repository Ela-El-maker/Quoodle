#include "ed25519_wrapper.hpp"
#include "utils/logger.hpp"

#ifdef HAVE_SODIUM
#include <sodium.h>
#include <vector>
#include <cstdlib>
#include <cstring>
#endif

std::string ed25519_sign_message(const std::string &message)
{
#ifdef HAVE_SODIUM
    if (sodium_init() < 0)
    {
        utils::log_error("ed25519_wrapper: sodium_init failed");
        return {};
    }

    const char *b64 = std::getenv("KERNEL_ED25519_SK_B64");
    if (!b64)
    {
        utils::log_warn("ed25519_wrapper: KERNEL_ED25519_SK_B64 not set; cannot sign");
        return {};
    }

    std::vector<unsigned char> sk(64);
    size_t bin_len = 0;
    if (sodium_base642bin(sk.data(), sk.size(), b64, strlen(b64), NULL, &bin_len, NULL, sodium_base64_VARIANT_ORIGINAL) != 0)
    {
        utils::log_error("ed25519_wrapper: failed to decode base64 SK");
        return {};
    }
    if (bin_len != 64)
    {
        utils::log_error("ed25519_wrapper: decoded SK has unexpected length");
        return {};
    }

    unsigned char sig[crypto_sign_BYTES];
    if (crypto_sign_detached(sig, NULL, reinterpret_cast<const unsigned char *>(message.data()), message.size(), sk.data()) != 0)
    {
        utils::log_error("ed25519_wrapper: crypto_sign_detached failed");
        return {};
    }

    // encode to base64
    char out[crypto_sign_BYTES * 2 + 16];
    sodium_bin2base64(out, sizeof(out), sig, crypto_sign_BYTES, sodium_base64_VARIANT_ORIGINAL);
    return std::string(out);
#else
    (void)message;
    utils::log_warn("ed25519_wrapper: libsodium not available at build time; fallback signing used");
    return {};
#endif
}
