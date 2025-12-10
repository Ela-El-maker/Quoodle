#pragma once

#include <stddef.h>
#include <stdint.h>

int ed25519_verify(const uint8_t* signature, const uint8_t* message, size_t message_len, const uint8_t* public_key);
