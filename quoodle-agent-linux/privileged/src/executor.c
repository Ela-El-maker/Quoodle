#include "executor.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int executor_handle_request(const char *json_request, char **json_response) {
    (void)json_request;
    const char *resp = "{\"status\":\"denied\",\"error\":{\"type\":\"ERR_CAPABILITY_NOT_SUPPORTED\",\"code\":1005}}";
    *json_response = strdup(resp);
    if (!*json_response) {
        return -1;
    }
    printf("Executor skeleton: capability not supported.\n");
    return 0;
}
