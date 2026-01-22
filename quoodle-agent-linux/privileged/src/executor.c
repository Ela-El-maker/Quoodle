#include "executor.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"

static char *dup_json(cJSON *obj) {
    char *out = cJSON_PrintUnformatted(obj);
    return out;
}

static char *build_error(const char *type, int code, const char *message) {
    cJSON *resp = cJSON_CreateObject();
    cJSON_AddStringToObject(resp, "status", "denied");
    cJSON *err = cJSON_CreateObject();
    cJSON_AddStringToObject(err, "type", type);
    cJSON_AddNumberToObject(err, "code", code);
    if (message) {
        cJSON_AddStringToObject(err, "message", message);
    }
    cJSON_AddItemToObject(resp, "error", err);
    char *out = dup_json(resp);
    cJSON_Delete(resp);
    return out;
}

int executor_handle_request(const char *json_request, char **json_response) {
    if (!json_request || !json_response) {
        return -1;
    }

    cJSON *root = cJSON_Parse(json_request);
    if (!root) {
        *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "invalid JSON");
        return *json_response ? 0 : -1;
    }

    const cJSON *cap = cJSON_GetObjectItem(root, "capability");
    if (!cap || !cJSON_IsString(cap) || !cap->valuestring) {
        cJSON_Delete(root);
        *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing capability");
        return *json_response ? 0 : -1;
    }

    if (strcmp(cap->valuestring, "CAP_LOCK_SESSION") == 0) {
        cJSON *resp = cJSON_CreateObject();
        cJSON_AddStringToObject(resp, "status", "ok");
        cJSON *result = cJSON_CreateObject();
        cJSON_AddNumberToObject(result, "session_count_locked", 1);
        cJSON_AddItemToObject(resp, "result", result);
        char *out = dup_json(resp);
        cJSON_Delete(resp);
        cJSON_Delete(root);
        *json_response = out;
        return out ? 0 : -1;
    }

    if (strcmp(cap->valuestring, "CAP_DISCOVERY") == 0) {
        cJSON *resp = cJSON_CreateObject();
        cJSON_AddStringToObject(resp, "status", "ok");
        cJSON *result = cJSON_CreateObject();
        cJSON *caps = cJSON_CreateArray();
        cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_LOCK_SESSION"));
        cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_DISCOVERY"));
        cJSON_AddItemToObject(result, "supported_caps", caps);
        cJSON_AddItemToObject(result, "attestation_methods", cJSON_CreateArray());
        cJSON_AddItemToObject(resp, "result", result);
        char *out = dup_json(resp);
        cJSON_Delete(resp);
        cJSON_Delete(root);
        *json_response = out;
        return out ? 0 : -1;
    }

    cJSON_Delete(root);
    *json_response = build_error("ERR_CAPABILITY_NOT_SUPPORTED", 1005, "capability not supported");
    return *json_response ? 0 : -1;
}
