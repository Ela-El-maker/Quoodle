#include "crypto.h"

#include <sodium.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int quoodle_sign_ed25519(const char *priv_b64, const char *msg, char **sig_b64) {
    if (!priv_b64 || !msg || !sig_b64) {
        return -1;
    }
    if (sodium_init() < 0) {
        return -1;
    }

    unsigned char keybuf[crypto_sign_SECRETKEYBYTES];
    size_t key_len = 0;
    if (sodium_base642bin(keybuf, sizeof(keybuf), priv_b64, strlen(priv_b64), NULL, &key_len, NULL,
                          sodium_base64_VARIANT_ORIGINAL) != 0) {
        return -1;
    }

    unsigned char sk[crypto_sign_SECRETKEYBYTES];
    if (key_len == crypto_sign_SECRETKEYBYTES) {
        memcpy(sk, keybuf, key_len);
    } else if (key_len == crypto_sign_SEEDBYTES) {
        unsigned char pk[crypto_sign_PUBLICKEYBYTES];
        crypto_sign_seed_keypair(pk, sk, keybuf);
    } else {
        return -1;
    }

    unsigned char sig[crypto_sign_BYTES];
    crypto_sign_detached(sig, NULL, (const unsigned char *)msg, strlen(msg), sk);

    size_t b64_len = sodium_base64_ENCODED_LEN(crypto_sign_BYTES, sodium_base64_VARIANT_ORIGINAL);
    char *out = (char *)malloc(b64_len);
    if (!out) {
        return -1;
    }
    sodium_bin2base64(out, b64_len, sig, crypto_sign_BYTES, sodium_base64_VARIANT_ORIGINAL);
    *sig_b64 = out;
    return 0;
}

int quoodle_verify_ed25519(const char *pub_b64, const char *msg, const char *sig_b64) {
    if (!pub_b64 || !msg || !sig_b64) {
        return -1;
    }
    if (sodium_init() < 0) {
        return -1;
    }

    unsigned char pk[crypto_sign_PUBLICKEYBYTES];
    size_t pk_len = 0;
    if (sodium_base642bin(pk, sizeof(pk), pub_b64, strlen(pub_b64), NULL, &pk_len, NULL,
                          sodium_base64_VARIANT_ORIGINAL) != 0) {
        return -1;
    }
    if (pk_len != crypto_sign_PUBLICKEYBYTES) {
        return -1;
    }

    unsigned char sig[crypto_sign_BYTES];
    size_t sig_len = 0;
    if (sodium_base642bin(sig, sizeof(sig), sig_b64, strlen(sig_b64), NULL, &sig_len, NULL,
                          sodium_base64_VARIANT_ORIGINAL) != 0) {
        return -1;
    }
    if (sig_len != crypto_sign_BYTES) {
        return -1;
    }

    if (crypto_sign_verify_detached(sig, (const unsigned char *)msg, strlen(msg), pk) != 0) {
        return -1;
    }
    return 0;
}
