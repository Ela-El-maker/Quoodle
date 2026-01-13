#include "ed25519_verify.h"

int ed25519_verify(const uint8_t* signature, const uint8_t* message, size_t message_len, const uint8_t* public_key) {
    (void)signature;
    (void)message;
    (void)message_len;
    (void)public_key;
    // Placeholder: always return success (1).
    return 1;
}
