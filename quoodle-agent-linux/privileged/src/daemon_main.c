#include <stdio.h>
#include <stdlib.h>

#include "uds_server.h"

static const char *getenv_or_default(const char *name, const char *fallback) {
    const char *val = getenv(name);
    return (val && *val) ? val : fallback;
}

int main(void) {
    const char *socket_path = getenv_or_default("QUOODLE_PRIV_SOCKET", "/run/quoodle/privileged.sock");
    printf("Starting privileged daemon skeleton on %s\n", socket_path);
    return uds_server_run(socket_path);
}
