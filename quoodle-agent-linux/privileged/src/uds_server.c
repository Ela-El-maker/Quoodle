#define _GNU_SOURCE
#define _XOPEN_SOURCE 700
#include "uds_server.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#include "cJSON.h"

#include "crypto.h"
#include "executor.h"
#include "jcs.h"
#include "state_store.h"

static const size_t k_max_payload = 1024 * 1024;

static const char *getenv_or_default(const char *name, const char *fallback) {
    const char *val = getenv(name);
    return (val && *val) ? val : fallback;
}

static int mkdir_p(const char *path, mode_t mode) {
    if (!path || !*path) {
        return -1;
    }
    char tmp[PATH_MAX];
    size_t len = strlen(path);
    if (len >= sizeof(tmp)) {
        return -1;
    }
    memcpy(tmp, path, len + 1);
    for (size_t i = 1; i < len; ++i) {
        if (tmp[i] == '/') {
            tmp[i] = '\0';
            if (mkdir(tmp, mode) != 0 && errno != EEXIST) {
                return -1;
            }
            tmp[i] = '/';
        }
    }
    if (mkdir(tmp, mode) != 0 && errno != EEXIST) {
        return -1;
    }
    return 0;
}

static int ensure_socket_dir(const char *socket_path) {
    char dir[PATH_MAX];
    const char *slash = strrchr(socket_path, '/');
    if (!slash) {
        return 0;
    }
    size_t len = (size_t)(slash - socket_path);
    if (len >= sizeof(dir)) {
        return -1;
    }
    memcpy(dir, socket_path, len);
    dir[len] = '\0';
    return mkdir_p(dir, 0755);
}

static int read_full(int fd, void *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t r = read(fd, (char *)buf + off, len - off);
        if (r == 0) {
            return 0;
        }
        if (r < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        off += (size_t)r;
    }
    return 1;
}

static int write_full(int fd, const void *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t w = write(fd, (const char *)buf + off, len - off);
        if (w < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        off += (size_t)w;
    }
    return 0;
}

static int send_frame(int fd, const char *payload) {
    uint32_t len = payload ? (uint32_t)strlen(payload) : 0;
    uint32_t net_len = htonl(len);
    if (write_full(fd, &net_len, sizeof(net_len)) != 0) {
        return -1;
    }
    if (len == 0) {
        return 0;
    }
    return write_full(fd, payload, len);
}

static char *read_frame(int fd) {
    uint32_t net_len = 0;
    int rc = read_full(fd, &net_len, sizeof(net_len));
    if (rc <= 0) {
        return NULL;
    }
    uint32_t len = ntohl(net_len);
    if (len == 0 || len > k_max_payload) {
        return NULL;
    }
    char *buf = (char *)malloc(len + 1);
    if (!buf) {
        return NULL;
    }
    rc = read_full(fd, buf, len);
    if (rc <= 0) {
        free(buf);
        return NULL;
    }
    buf[len] = '\0';
    return buf;
}

static int check_peer_creds(int fd) {
    struct ucred cred;
    socklen_t len = sizeof(cred);
    if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) != 0) {
        return -1;
    }
    const char *uid_env = getenv("QUOODLE_PRIV_ALLOWED_UID");
    if (uid_env && *uid_env) {
        long uid = strtol(uid_env, NULL, 10);
        if ((uid_t)uid != cred.uid) {
            return -1;
        }
    }
    const char *gid_env = getenv("QUOODLE_PRIV_ALLOWED_GID");
    if (gid_env && *gid_env) {
        long gid = strtol(gid_env, NULL, 10);
        if ((gid_t)gid != cred.gid) {
            return -1;
        }
    }
    return 0;
}

static void iso_timestamp(char *buf, size_t len) {
    time_t now = time(NULL);
    struct tm tmv;
    gmtime_r(&now, &tmv);
    strftime(buf, len, "%Y-%m-%dT%H:%M:%SZ", &tmv);
}

static int parse_basic_timestamp(const char *ts) {
    if (!ts) {
        return -1;
    }
    struct tm tmv;
    memset(&tmv, 0, sizeof(tmv));
    char *out = strptime(ts, "%Y-%m-%dT%H:%M:%SZ", &tmv);
    return (out && *out == '\0') ? 0 : -1;
}

static int is_safe_id(const char *value) {
    if (!value || !*value) {
        return 0;
    }
    for (const unsigned char *p = (const unsigned char *)value; *p; ++p) {
        if ((*p >= 'a' && *p <= 'z') ||
            (*p >= 'A' && *p <= 'Z') ||
            (*p >= '0' && *p <= '9') ||
            *p == '-') {
            continue;
        }
        return 0;
    }
    return 1;
}

static int read_uuid(char *buf, size_t len) {
    int fd = open("/proc/sys/kernel/random/uuid", O_RDONLY);
    if (fd < 0) {
        return -1;
    }
    ssize_t r = read(fd, buf, len - 1);
    close(fd);
    if (r <= 0) {
        return -1;
    }
    buf[r] = '\0';
    char *nl = strchr(buf, '\n');
    if (nl) {
        *nl = '\0';
    }
    return 0;
}

static char *canonicalize_without_sig(cJSON *root) {
    if (!root) {
        return NULL;
    }
    cJSON *copy = cJSON_Duplicate(root, 1);
    if (!copy) {
        return NULL;
    }
    cJSON *sig = cJSON_GetObjectItem(copy, "sig");
    if (sig && cJSON_IsObject(sig)) {
        cJSON *sig_val = cJSON_GetObjectItem(sig, "sig");
        if (sig_val) {
            cJSON_SetValuestring(sig_val, "");
        } else {
            cJSON_AddStringToObject(sig, "sig", "");
        }
    }
    char *raw = cJSON_PrintUnformatted(copy);
    cJSON_Delete(copy);
    if (!raw) {
        return NULL;
    }
    char *canonical = NULL;
    if (jcs_canonicalize(raw, &canonical) != 0) {
        free(raw);
        return NULL;
    }
    free(raw);
    return canonical;
}

static cJSON *build_base_response(const char *request_id, const char *status) {
    cJSON *resp = cJSON_CreateObject();
    if (!resp) {
        return NULL;
    }
    cJSON_AddStringToObject(resp, "request_id", request_id ? request_id : "unknown");
    cJSON_AddStringToObject(resp, "status", status ? status : "error");

    char exec_id[64] = {0};
    if (read_uuid(exec_id, sizeof(exec_id)) != 0) {
        snprintf(exec_id, sizeof(exec_id), "exec-%ld", (long)time(NULL));
    }
    cJSON_AddStringToObject(resp, "exec_id", exec_id);

    char ts[32] = {0};
    iso_timestamp(ts, sizeof(ts));
    cJSON_AddStringToObject(resp, "timestamp", ts);

    cJSON *sig = cJSON_CreateObject();
    if (!sig) {
        cJSON_Delete(resp);
        return NULL;
    }
    cJSON_AddStringToObject(sig, "alg", "Ed25519");
    cJSON_AddStringToObject(sig, "kid", getenv_or_default("QUOODLE_DAEMON_KID", "daemon-default"));
    cJSON_AddStringToObject(sig, "canon", "JCS-v1");
    cJSON_AddStringToObject(sig, "signer", "daemon");
    cJSON_AddStringToObject(sig, "sig", "");
    cJSON_AddItemToObject(resp, "sig", sig);
    return resp;
}

static char *finalize_and_sign_response(cJSON *resp) {
    const char *priv_b64 = getenv("QUOODLE_DAEMON_PRIVKEY_B64");
    if (!priv_b64 || !*priv_b64) {
        return NULL;
    }
    char *canonical = canonicalize_without_sig(resp);
    if (!canonical) {
        return NULL;
    }
    char *sig_b64 = NULL;
    if (quoodle_sign_ed25519(priv_b64, canonical, &sig_b64) != 0) {
        free(canonical);
        return NULL;
    }
    free(canonical);

    cJSON *sig = cJSON_GetObjectItem(resp, "sig");
    if (!sig || !cJSON_IsObject(sig)) {
        free(sig_b64);
        return NULL;
    }
    cJSON *sig_val = cJSON_GetObjectItem(sig, "sig");
    if (!sig_val) {
        cJSON_AddStringToObject(sig, "sig", sig_b64);
    } else {
        cJSON_SetValuestring(sig_val, sig_b64);
    }
    free(sig_b64);

    char *out = cJSON_PrintUnformatted(resp);
    return out;
}

static char *build_error_response(const char *request_id, const char *status, const char *etype, int code,
                                  const char *message) {
    cJSON *resp = build_base_response(request_id, status);
    if (!resp) {
        return NULL;
    }
    cJSON *err = cJSON_CreateObject();
    if (!err) {
        cJSON_Delete(resp);
        return NULL;
    }
    cJSON_AddStringToObject(err, "type", etype);
    cJSON_AddNumberToObject(err, "code", code);
    cJSON_AddStringToObject(err, "message", message ? message : "");
    cJSON_AddItemToObject(resp, "error", err);
    cJSON_AddNullToObject(resp, "result");

    char *out = finalize_and_sign_response(resp);
    cJSON_Delete(resp);
    return out;
}

static int validate_sig_object(cJSON *sig, const char **sig_b64_out) {
    if (!sig || !cJSON_IsObject(sig)) {
        return -1;
    }
    cJSON *sig_val = cJSON_GetObjectItem(sig, "sig");
    cJSON *signer = cJSON_GetObjectItem(sig, "signer");
    if (!sig_val || !cJSON_IsString(sig_val) || !sig_val->valuestring) {
        return -1;
    }
    if (signer && cJSON_IsString(signer)) {
        if (strcmp(signer->valuestring, "agent") != 0) {
            return -1;
        }
    }
    *sig_b64_out = sig_val->valuestring;
    return 0;
}

static char *handle_request(const char *json_in) {
    if (!json_in) {
        return build_error_response("unknown", "error", "ERR_SCHEMA_INVALID", 1001, "empty request");
    }
    cJSON *root = cJSON_Parse(json_in);
    if (!root || !cJSON_IsObject(root)) {
        if (root) {
            cJSON_Delete(root);
        }
        return build_error_response("unknown", "error", "ERR_SCHEMA_INVALID", 1001, "invalid JSON");
    }

    const char *request_id = NULL;
    cJSON *request_id_item = cJSON_GetObjectItem(root, "request_id");
    if (request_id_item && cJSON_IsString(request_id_item)) {
        request_id = request_id_item->valuestring;
    }

    cJSON *timestamp = cJSON_GetObjectItem(root, "timestamp");
    cJSON *capability = cJSON_GetObjectItem(root, "capability");
    cJSON *params = cJSON_GetObjectItem(root, "params");
    cJSON *agent_seq = cJSON_GetObjectItem(root, "agent_sequence");
    cJSON *policy_hash = cJSON_GetObjectItem(root, "policy_hash");
    cJSON *command_message_id = cJSON_GetObjectItem(root, "command_message_id");
    cJSON *sig = cJSON_GetObjectItem(root, "sig");

    if (!request_id || !timestamp || !capability || !params || !agent_seq || !policy_hash ||
        !command_message_id || !sig) {
        cJSON_Delete(root);
        return build_error_response(request_id ? request_id : "unknown", "error", "ERR_SCHEMA_INVALID", 1001,
                                    "missing required fields");
    }
    if (!is_safe_id(request_id)) {
        cJSON_Delete(root);
        return build_error_response("unknown", "error", "ERR_SCHEMA_INVALID", 1001, "invalid request_id");
    }
    if (!cJSON_IsString(timestamp) || !cJSON_IsString(capability) || !cJSON_IsObject(params) ||
        !cJSON_IsNumber(agent_seq) || !cJSON_IsString(policy_hash) || !cJSON_IsString(command_message_id)) {
        cJSON_Delete(root);
        return build_error_response(request_id, "error", "ERR_SCHEMA_INVALID", 1001, "invalid field types");
    }
    if (parse_basic_timestamp(timestamp->valuestring) != 0) {
        cJSON_Delete(root);
        return build_error_response(request_id, "error", "ERR_SCHEMA_INVALID", 1001, "invalid timestamp");
    }

    const char *sig_b64 = NULL;
    if (validate_sig_object(sig, &sig_b64) != 0) {
        cJSON_Delete(root);
        return build_error_response(request_id, "denied", "ERR_SIG_INVALID", 1002, "invalid signature");
    }

    const char *agent_pub_b64 = getenv("QUOODLE_AGENT_PUBKEY_B64");
    if (!agent_pub_b64 || !*agent_pub_b64) {
        cJSON_Delete(root);
        return build_error_response(request_id, "error", "ERR_SIG_INVALID", 1002, "missing agent public key");
    }

    char *canonical = canonicalize_without_sig(root);
    if (!canonical) {
        cJSON_Delete(root);
        return build_error_response(request_id, "error", "ERR_SCHEMA_INVALID", 1001, "canonicalization failed");
    }
    if (quoodle_verify_ed25519(agent_pub_b64, canonical, sig_b64) != 0) {
        free(canonical);
        cJSON_Delete(root);
        return build_error_response(request_id, "denied", "ERR_SIG_INVALID", 1002, "signature verification failed");
    }
    free(canonical);

    char *cached = NULL;
    int cached_rc = state_store_get_response(request_id, &cached);
    if (cached_rc == 1 && cached) {
        cJSON_Delete(root);
        return cached;
    } else if (cached_rc < 0) {
        cJSON_Delete(root);
        return build_error_response(request_id, "error", "ERR_EXECUTION_FAILED", 2001, "idempotency cache error");
    }

    long last_seq = 0;
    if (state_store_load_sequence(NULL, &last_seq) != 0) {
        cJSON_Delete(root);
        return build_error_response(request_id, "error", "ERR_EXECUTION_FAILED", 2001, "sequence load failed");
    }
    long req_seq = (long)agent_seq->valuedouble;
    if (req_seq <= last_seq) {
        cJSON_Delete(root);
        return build_error_response(request_id, "denied", "ERR_REPLAY_DETECTED", 1003, "sequence regression");
    }

    char *exec_resp = NULL;
    if (executor_handle_request(json_in, &exec_resp) != 0 || !exec_resp) {
        cJSON_Delete(root);
        return build_error_response(request_id, "error", "ERR_EXECUTION_FAILED", 2001, "executor failed");
    }

    cJSON *exec_root = cJSON_Parse(exec_resp);
    free(exec_resp);
    if (!exec_root || !cJSON_IsObject(exec_root)) {
        if (exec_root) {
            cJSON_Delete(exec_root);
        }
        cJSON_Delete(root);
        return build_error_response(request_id, "error", "ERR_EXECUTION_FAILED", 2001, "executor invalid response");
    }

    const char *status = "ok";
    cJSON *exec_status = cJSON_GetObjectItem(exec_root, "status");
    if (exec_status && cJSON_IsString(exec_status) && exec_status->valuestring) {
        status = exec_status->valuestring;
    }

    cJSON *resp = build_base_response(request_id, status);
    if (!resp) {
        cJSON_Delete(exec_root);
        cJSON_Delete(root);
        return build_error_response(request_id, "error", "ERR_EXECUTION_FAILED", 2001, "response build failed");
    }

    cJSON *exec_err = cJSON_GetObjectItem(exec_root, "error");
    if (exec_err) {
        cJSON_AddItemToObject(resp, "error", cJSON_Duplicate(exec_err, 1));
    } else {
        cJSON_AddNullToObject(resp, "error");
    }
    cJSON *exec_result = cJSON_GetObjectItem(exec_root, "result");
    if (exec_result) {
        cJSON_AddItemToObject(resp, "result", cJSON_Duplicate(exec_result, 1));
    } else {
        cJSON_AddNullToObject(resp, "result");
    }

    char *out = finalize_and_sign_response(resp);
    cJSON_Delete(exec_root);
    cJSON_Delete(resp);
    cJSON_Delete(root);
    if (!out) {
        return build_error_response(request_id, "error", "ERR_EXECUTION_FAILED", 2001, "signing failed");
    }

    if (state_store_save_response(request_id, out) != 0) {
        free(out);
        return build_error_response(request_id, "error", "ERR_EXECUTION_FAILED", 2001, "response persistence failed");
    }
    if (state_store_save_sequence(NULL, req_seq) != 0) {
        free(out);
        return build_error_response(request_id, "error", "ERR_EXECUTION_FAILED", 2001, "sequence persistence failed");
    }
    return out;
}

int uds_server_run(const char *socket_path) {
    if (!socket_path || !*socket_path) {
        fprintf(stderr, "Missing socket path.\n");
        return -1;
    }
    const char *priv_key = getenv("QUOODLE_DAEMON_PRIVKEY_B64");
    const char *agent_pub = getenv("QUOODLE_AGENT_PUBKEY_B64");
    if (!priv_key || !*priv_key || !agent_pub || !*agent_pub) {
        fprintf(stderr, "Missing QUOODLE_DAEMON_PRIVKEY_B64 or QUOODLE_AGENT_PUBKEY_B64.\n");
        return -1;
    }

    if (ensure_socket_dir(socket_path) != 0) {
        fprintf(stderr, "Failed to create socket directory.\n");
        return -1;
    }

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        perror("socket");
        return -1;
    }
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);
    unlink(socket_path);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        perror("bind");
        close(fd);
        return -1;
    }
    if (chmod(socket_path, 0660) != 0) {
        perror("chmod");
    }
    if (listen(fd, 8) != 0) {
        perror("listen");
        close(fd);
        return -1;
    }

    printf("Privileged daemon listening on %s\n", socket_path);

    for (;;) {
        int cfd = accept(fd, NULL, NULL);
        if (cfd < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("accept");
            break;
        }
        if (check_peer_creds(cfd) != 0) {
            close(cfd);
            continue;
        }
        for (;;) {
            char *payload = read_frame(cfd);
            if (!payload) {
                break;
            }
            char *response = handle_request(payload);
            free(payload);
            if (response) {
                send_frame(cfd, response);
                free(response);
            } else {
                send_frame(cfd, "{\"status\":\"error\"}");
            }
        }
        close(cfd);
    }

    close(fd);
    unlink(socket_path);
    return 0;
}
