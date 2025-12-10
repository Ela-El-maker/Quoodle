#include <stdio.h>

void canonicalize_json(const char* input, char* output, size_t out_len) {
    snprintf(output, out_len, "%s", input);
}
