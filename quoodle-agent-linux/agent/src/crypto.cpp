#include "crypto.h"

#include <sodium.h>

#include <stdexcept>
#include <vector>

namespace {

std::vector<unsigned char> DecodeBase64(const std::string &b64) {
    std::vector<unsigned char> out(b64.size());
    size_t out_len = 0;
    if (sodium_base642bin(out.data(), out.size(), b64.c_str(), b64.size(), nullptr, &out_len, nullptr,
                          sodium_base64_VARIANT_ORIGINAL) != 0) {
        throw std::runtime_error("Invalid base64");
    }
    out.resize(out_len);
    return out;
}

std::string EncodeBase64(const unsigned char *data, size_t len) {
    size_t out_len = sodium_base64_ENCODED_LEN(len, sodium_base64_VARIANT_ORIGINAL);
    std::string out(out_len, '\0');
    sodium_bin2base64(out.data(), out_len, data, len, sodium_base64_VARIANT_ORIGINAL);
    if (!out.empty() && out.back() == '\0') {
        out.pop_back();
    }
    return out;
}

}  // namespace

namespace quoodle {

std::string SignEd25519(const std::string &priv_b64, const std::string &message) {
    if (sodium_init() < 0) {
        throw std::runtime_error("libsodium init failed");
    }

    auto key = DecodeBase64(priv_b64);
    unsigned char sk[crypto_sign_SECRETKEYBYTES];
    if (key.size() == crypto_sign_SECRETKEYBYTES) {
        std::copy(key.begin(), key.end(), sk);
    } else if (key.size() == crypto_sign_SEEDBYTES) {
        unsigned char pk[crypto_sign_PUBLICKEYBYTES];
        crypto_sign_seed_keypair(pk, sk, key.data());
    } else {
        throw std::runtime_error("Unexpected Ed25519 key size");
    }

    unsigned char sig[crypto_sign_BYTES];
    crypto_sign_detached(sig, nullptr, reinterpret_cast<const unsigned char *>(message.data()), message.size(), sk);
    return EncodeBase64(sig, crypto_sign_BYTES);
}

bool VerifyEd25519(const std::string &pub_b64, const std::string &message, const std::string &sig_b64) {
    if (sodium_init() < 0) {
        return false;
    }
    auto pk = DecodeBase64(pub_b64);
    auto sig = DecodeBase64(sig_b64);
    if (pk.size() != crypto_sign_PUBLICKEYBYTES || sig.size() != crypto_sign_BYTES) {
        return false;
    }
    int rc = crypto_sign_verify_detached(sig.data(),
                                         reinterpret_cast<const unsigned char *>(message.data()),
                                         message.size(),
                                         pk.data());
    return rc == 0;
}

}  // namespace quoodle
