#include "state_store.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static const char *state_dir_default = "/var/lib/quoodle";

static const char *get_state_dir(void) {
    const char *env = getenv("QUOODLE_PRIV_STATE_DIR");
    if (env && *env) {
        return env;
    }
    return state_dir_default;
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

static int ensure_dir(const char *path) {
    struct stat st;
    if (stat(path, &st) == 0) {
        return S_ISDIR(st.st_mode) ? 0 : -1;
    }
    if (mkdir_p(path, 0750) != 0) {
        return -1;
    }
    return 0;
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

int state_store_load_sequence(const char *device_id, long *last_seq) {
    (void)device_id;
    if (!last_seq) {
        return -1;
    }
    *last_seq = 0;
    const char *dir = get_state_dir();
    if (ensure_dir(dir) != 0) {
        return -1;
    }

    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/sequence.txt", dir);
    FILE *fp = fopen(path, "r");
    if (!fp) {
        if (errno == ENOENT) {
            return 0;
        }
        return -1;
    }
    long seq = 0;
    if (fscanf(fp, "%ld", &seq) != 1) {
        fclose(fp);
        return -1;
    }
    fclose(fp);
    *last_seq = seq;
    return 0;
}

int state_store_save_sequence(const char *device_id, long seq) {
    (void)device_id;
    const char *dir = get_state_dir();
    if (ensure_dir(dir) != 0) {
        return -1;
    }

    char path[PATH_MAX];
    char tmp[PATH_MAX];
    snprintf(path, sizeof(path), "%s/sequence.txt", dir);
    snprintf(tmp, sizeof(tmp), "%s/sequence.txt.tmp", dir);

    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0640);
    if (fd < 0) {
        return -1;
    }
    char buf[64];
    int len = snprintf(buf, sizeof(buf), "%ld\n", seq);
    if (write(fd, buf, (size_t)len) != len) {
        close(fd);
        return -1;
    }
    fsync(fd);
    close(fd);
    if (rename(tmp, path) != 0) {
        return -1;
    }
    return 0;
}

int state_store_get_response(const char *request_id, char **json_response_out) {
    if (!json_response_out || !is_safe_id(request_id)) {
        return -1;
    }
    *json_response_out = NULL;
    const char *dir = get_state_dir();
    if (ensure_dir(dir) != 0) {
        return -1;
    }
    char resp_dir[PATH_MAX];
    snprintf(resp_dir, sizeof(resp_dir), "%s/responses", dir);
    if (ensure_dir(resp_dir) != 0) {
        return -1;
    }
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/%s.json", resp_dir, request_id);

    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        if (errno == ENOENT) {
            return 0;
        }
        return -1;
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size <= 0) {
        close(fd);
        return -1;
    }
    char *buf = (char *)malloc((size_t)st.st_size + 1);
    if (!buf) {
        close(fd);
        return -1;
    }
    ssize_t read_bytes = read(fd, buf, (size_t)st.st_size);
    close(fd);
    if (read_bytes != st.st_size) {
        free(buf);
        return -1;
    }
    buf[read_bytes] = '\0';
    *json_response_out = buf;
    return 1;
}

int state_store_save_response(const char *request_id, const char *json_response) {
    if (!json_response || !is_safe_id(request_id)) {
        return -1;
    }
    const char *dir = get_state_dir();
    if (ensure_dir(dir) != 0) {
        return -1;
    }
    char resp_dir[PATH_MAX];
    snprintf(resp_dir, sizeof(resp_dir), "%s/responses", dir);
    if (ensure_dir(resp_dir) != 0) {
        return -1;
    }
    char path[PATH_MAX];
    char tmp[PATH_MAX];
    snprintf(path, sizeof(path), "%s/%s.json", resp_dir, request_id);
    snprintf(tmp, sizeof(tmp), "%s/%s.json.tmp", resp_dir, request_id);

    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0640);
    if (fd < 0) {
        return -1;
    }
    size_t len = strlen(json_response);
    if (write(fd, json_response, len) != (ssize_t)len) {
        close(fd);
        return -1;
    }
    fsync(fd);
    close(fd);
    if (rename(tmp, path) != 0) {
        return -1;
    }
    return 0;
}
