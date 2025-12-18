#include "ed25519_verify_wrapper.hpp"
#include "utils/logger.hpp"

#ifdef HAVE_SODIUM
#include <sodium.h>
#include <vector>
#include <cstring>
#endif

bool ed25519_verify_message(const std::string &message, const std::string &sig_b64, const std::string &pubkey_b64)
{
#ifdef HAVE_SODIUM
    if (sodium_init() < 0)
    {
        utils::log_error("ed25519_verify: sodium_init failed");
        return false;
    }

    std::vector<unsigned char> sig(crypto_sign_BYTES);
    size_t sig_len = 0;
    if (sodium_base642bin(sig.data(), sig.size(), sig_b64.c_str(), sig_b64.size(), NULL, &sig_len, NULL, sodium_base64_VARIANT_ORIGINAL) != 0)
    {
        utils::log_error("ed25519_verify: failed to decode signature base64");
        return false;
    }
    if (sig_len != crypto_sign_BYTES)
    {
        utils::log_error("ed25519_verify: signature has unexpected length");
        return false;
    }

    std::vector<unsigned char> pk(crypto_sign_PUBLICKEYBYTES);
    size_t pk_len = 0;
    if (sodium_base642bin(pk.data(), pk.size(), pubkey_b64.c_str(), pubkey_b64.size(), NULL, &pk_len, NULL, sodium_base64_VARIANT_ORIGINAL) != 0)
    {
        utils::log_error("ed25519_verify: failed to decode pubkey base64");
        return false;
    }
    if (pk_len != crypto_sign_PUBLICKEYBYTES)
    {
        utils::log_error("ed25519_verify: pubkey has unexpected length");
        return false;
    }

    int ok = crypto_sign_verify_detached(sig.data(), reinterpret_cast<const unsigned char *>(message.data()), message.size(), pk.data());
    return ok == 0;
#else
    (void)message;
    (void)sig_b64;
    (void)pubkey_b64;
    utils::log_warn("ed25519_verify: libsodium not available; refusing verification");
    return false;
#endif
}
