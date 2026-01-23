#include "executor.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <pwd.h>
#include <grp.h>
#include <sys/types.h>
#include <unistd.h>

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

static char *build_failure(const char *type, int code, const char *message) {
    cJSON *resp = cJSON_CreateObject();
    cJSON_AddStringToObject(resp, "status", "failed");
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

static int run_cmd(char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) {
        return -1;
    }
    if (pid == 0) {
        execvp(argv[0], argv);
        _exit(127);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        return -1;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return -1;
}

static int run_cmd_as_user(const char *user, const char *uid_str, char *const argv[]) {
    uid_t uid = 0;
    if (uid_str && *uid_str) {
        uid = (uid_t)strtoul(uid_str, NULL, 10);
    }
    struct passwd *pw = uid ? getpwuid(uid) : (user ? getpwnam(user) : NULL);
    if (!pw) {
        return -1;
    }

    char dbus_addr[128];
    char runtime_dir[64];
    snprintf(dbus_addr, sizeof(dbus_addr), "unix:path=/run/user/%u/bus", (unsigned)pw->pw_uid);
    snprintf(runtime_dir, sizeof(runtime_dir), "/run/user/%u", (unsigned)pw->pw_uid);

    pid_t pid = fork();
    if (pid < 0) {
        return -1;
    }
    if (pid == 0) {
        setenv("DBUS_SESSION_BUS_ADDRESS", dbus_addr, 1);
        setenv("XDG_RUNTIME_DIR", runtime_dir, 1);
        if (user) {
            initgroups(user, pw->pw_gid);
        }
        setgid(pw->pw_gid);
        setuid(pw->pw_uid);
        execvp(argv[0], argv);
        _exit(127);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        return -1;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return -1;
}

static int lock_sessions_via_loginctl(int *locked_count) {
    char *const lock_all[] = {"loginctl", "lock-sessions", NULL};
    int rc = run_cmd(lock_all);
    if (rc == 0) {
        if (locked_count) {
            *locked_count = 1;
        }
        return 0;
    }
    return -1;
}

static int lock_sessions_individual(int *locked_count) {
    FILE *fp = popen("loginctl list-sessions --no-legend", "r");
    if (!fp) {
        return -1;
    }

    int locked = 0;
    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        char session[32] = {0};
        char uid[32] = {0};
        char user[64] = {0};
        if (sscanf(line, "%31s %31s %63s", session, uid, user) < 2) {
            continue;
        }
        char *const argv[] = {"loginctl", "lock-session", session, NULL};
        if (run_cmd(argv) == 0) {
            locked++;
        }
    }
    pclose(fp);
    if (locked_count) {
        *locked_count = locked;
    }
    return locked > 0 ? 0 : -1;
}

static int lock_sessions_via_qdbus(void) {
    FILE *fp = popen("loginctl list-sessions --no-legend", "r");
    if (!fp) {
        return -1;
    }

    int locked = 0;
    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        char session[32] = {0};
        char uid[32] = {0};
        char user[64] = {0};
        if (sscanf(line, "%31s %31s %63s", session, uid, user) < 2) {
            continue;
        }

        char *const qdbus_args[] = {"qdbus", "org.freedesktop.ScreenSaver", "/ScreenSaver", "Lock", NULL};
        if (run_cmd_as_user(user, uid, qdbus_args) == 0) {
            locked++;
            continue;
        }
        char *const qdbus6_args[] = {"qdbus6", "org.freedesktop.ScreenSaver", "/ScreenSaver", "Lock", NULL};
        if (run_cmd_as_user(user, uid, qdbus6_args) == 0) {
            locked++;
            continue;
        }
        char *const dbus_send_args[] = {
            "dbus-send",
            "--session",
            "--dest=org.freedesktop.ScreenSaver",
            "/ScreenSaver",
            "org.freedesktop.ScreenSaver.Lock",
            NULL,
        };
        if (run_cmd_as_user(user, uid, dbus_send_args) == 0) {
            locked++;
            continue;
        }
    }
    pclose(fp);
    return locked > 0 ? 0 : -1;
}

static int run_lock_sessions(int *locked_count) {
    int locked = 0;
    if (lock_sessions_via_loginctl(&locked) == 0) {
        if (locked_count) {
            *locked_count = locked > 0 ? locked : 1;
        }
        return 0;
    }
    if (lock_sessions_individual(&locked) == 0) {
        if (locked_count) {
            *locked_count = locked;
        }
        return 0;
    }
    if (lock_sessions_via_qdbus() == 0) {
        if (locked_count) {
            *locked_count = 1;
        }
        return 0;
    }
    if (locked_count) {
        *locked_count = 0;
    }
    return -1;
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
        int locked = 0;
        int rc = run_lock_sessions(&locked);
        if (rc != 0) {
            cJSON_Delete(root);
            *json_response = build_failure("ERR_EXECUTION_FAILED", 2001, "screen lock failed");
            return *json_response ? 0 : -1;
        }
        cJSON *resp = cJSON_CreateObject();
        cJSON_AddStringToObject(resp, "status", "ok");
        cJSON *result = cJSON_CreateObject();
        cJSON_AddNumberToObject(result, "session_count_locked", locked);
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
