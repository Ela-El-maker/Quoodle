#include "executor.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <sys/wait.h>
#include <pwd.h>
#include <grp.h>
#include <limits.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/sysinfo.h>
#include <sys/utsname.h>
#include <unistd.h>
#include <dirent.h>
#include <ctype.h>
#include <time.h>
#include <stdbool.h>
#include <regex.h>
#include <libgen.h>

#include <sodium.h>

#include "cJSON.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

typedef struct
{
  char session[32];
  char uid[32];
  char user[64];
  char state[32];
  char type[32];
  char display[64];
  char idle_usec[64];
  int active;
} SessionInfo;

static int select_active_session(SessionInfo *selected);

static char *dup_json(cJSON *obj)
{
  char *out = cJSON_PrintUnformatted(obj);
  return out;
}

static char *build_error(const char *type, int code, const char *message)
{
  cJSON *resp = cJSON_CreateObject();
  cJSON_AddStringToObject(resp, "status", "denied");
  cJSON *err = cJSON_CreateObject();
  cJSON_AddStringToObject(err, "type", type);
  cJSON_AddNumberToObject(err, "code", code);
  if (message)
  {
    cJSON_AddStringToObject(err, "message", message);
  }
  cJSON_AddItemToObject(resp, "error", err);
  char *out = dup_json(resp);
  cJSON_Delete(resp);
  return out;
}

static char *build_failure(const char *type, int code, const char *message)
{
  cJSON *resp = cJSON_CreateObject();
  cJSON_AddStringToObject(resp, "status", "failed");
  cJSON *err = cJSON_CreateObject();
  cJSON_AddStringToObject(err, "type", type);
  cJSON_AddNumberToObject(err, "code", code);
  if (message)
  {
    cJSON_AddStringToObject(err, "message", message);
  }
  cJSON_AddItemToObject(resp, "error", err);
  char *out = dup_json(resp);
  cJSON_Delete(resp);
  return out;
}

static char *build_success(cJSON *result)
{
  cJSON *resp = cJSON_CreateObject();
  cJSON_AddStringToObject(resp, "status", "ok");
  if (result)
  {
    cJSON_AddItemToObject(resp, "result", result);
  }
  else
  {
    cJSON_AddItemToObject(resp, "result", cJSON_CreateObject());
  }
  char *out = dup_json(resp);
  cJSON_Delete(resp);
  return out;
}

static void iso_timestamp(char *buf, size_t len)
{
  time_t now = time(NULL);
  struct tm tmv;
  gmtime_r(&now, &tmv);
  strftime(buf, len, "%Y-%m-%dT%H:%M:%SZ", &tmv);
}

static int run_cmd(char *const argv[])
{
  pid_t pid = fork();
  if (pid < 0)
  {
    return -1;
  }
  if (pid == 0)
  {
    execvp(argv[0], argv);
    _exit(127);
  }
  int status = 0;
  if (waitpid(pid, &status, 0) < 0)
  {
    return -1;
  }
  if (WIFEXITED(status))
  {
    return WEXITSTATUS(status);
  }
  return -1;
}

static int run_cmd_capture(const char *cmd, char *buf, size_t len)
{
  if (!cmd || !buf || len == 0)
  {
    return -1;
  }
  FILE *fp = popen(cmd, "r");
  if (!fp)
  {
    buf[0] = '\0';
    return -1;
  }
  size_t used = 0;
  buf[0] = '\0';
  while (used + 1 < len && fgets(buf + used, (int)(len - used), fp))
  {
    used = strlen(buf);
    if (used + 1 >= len)
    {
      break;
    }
  }
  int status = pclose(fp);
  if (status == -1)
  {
    return -1;
  }
  if (WIFEXITED(status))
  {
    return WEXITSTATUS(status);
  }
  return -1;
}

static int run_cmd_capture_argv(char *const argv[], char *buf, size_t len)
{
  if (!argv || !argv[0] || !buf || len == 0)
  {
    return -1;
  }

  int pipefd[2];
  if (pipe(pipefd) != 0)
  {
    return -1;
  }

  pid_t pid = fork();
  if (pid < 0)
  {
    close(pipefd[0]);
    close(pipefd[1]);
    return -1;
  }

  if (pid == 0)
  {
    dup2(pipefd[1], STDOUT_FILENO);
    dup2(pipefd[1], STDERR_FILENO);
    close(pipefd[0]);
    close(pipefd[1]);
    execvp(argv[0], argv);
    _exit(127);
  }

  close(pipefd[1]);
  size_t used = 0;
  buf[0] = '\0';
  ssize_t read_bytes = 0;
  while (used + 1 < len &&
         (read_bytes = read(pipefd[0], buf + used, len - used - 1)) > 0)
  {
    used += (size_t)read_bytes;
  }
  buf[used] = '\0';
  close(pipefd[0]);

  int status = 0;
  if (waitpid(pid, &status, 0) < 0)
  {
    return -1;
  }
  if (WIFEXITED(status))
  {
    return WEXITSTATUS(status);
  }
  return -1;
}

static const char *get_artifact_dir(void)
{
  const char *dir = getenv("QUOODLE_ARTIFACT_DIR");
  if (dir && *dir)
  {
    return dir;
  }
  return "/var/lib/quoodle/artifacts";
}

static int mkdir_p(const char *path, mode_t mode)
{
  if (!path || !*path)
  {
    return -1;
  }
  char tmp[PATH_MAX];
  size_t len = strlen(path);
  if (len >= sizeof(tmp))
  {
    return -1;
  }
  memcpy(tmp, path, len + 1);

  for (size_t i = 1; i < len; ++i)
  {
    if (tmp[i] == '/')
    {
      tmp[i] = '\0';
      if (mkdir(tmp, mode) != 0 && errno != EEXIST)
      {
        return -1;
      }
      tmp[i] = '/';
    }
  }
  if (mkdir(tmp, mode) != 0 && errno != EEXIST)
  {
    return -1;
  }
  return 0;
}

static int ensure_dir(const char *path)
{
  struct stat st;
  if (stat(path, &st) == 0)
  {
    return S_ISDIR(st.st_mode) ? 0 : -1;
  }
  return mkdir_p(path, 0750);
}

static const char *find_executable(const char *name, char *buf, size_t len)
{
  if (!name || !*name || !buf || len == 0)
  {
    return NULL;
  }
  const char *path_env = getenv("PATH");
  if (!path_env)
  {
    path_env = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
  }
  char path_copy[4096];
  snprintf(path_copy, sizeof(path_copy), "%s", path_env);
  char *saveptr = NULL;
  char *dir = strtok_r(path_copy, ":", &saveptr);
  while (dir)
  {
    snprintf(buf, len, "%s/%s", dir, name);
    if (access(buf, X_OK) == 0)
    {
      return buf;
    }
    dir = strtok_r(NULL, ":", &saveptr);
  }
  return NULL;
}

static void trim_trailing_whitespace(char *value)
{
  if (!value)
  {
    return;
  }
  size_t len = strlen(value);
  while (len > 0 && isspace((unsigned char)value[len - 1]))
  {
    value[--len] = '\0';
  }
}

static void trim_leading_whitespace(char *value)
{
  if (!value || !*value)
  {
    return;
  }
  char *start = value;
  while (*start && isspace((unsigned char)*start))
  {
    start++;
  }
  if (start != value)
  {
    memmove(value, start, strlen(start) + 1);
  }
}

static void copy_last_nonempty_line(const char *src, char *dst, size_t len)
{
  if (!dst || len == 0)
  {
    return;
  }
  dst[0] = '\0';
  if (!src || !*src)
  {
    return;
  }

  char buf[4096];
  snprintf(buf, sizeof(buf), "%s", src);
  char *saveptr = NULL;
  char *line = strtok_r(buf, "\n", &saveptr);
  char *last = NULL;
  while (line)
  {
    trim_leading_whitespace(line);
    trim_trailing_whitespace(line);
    if (*line)
    {
      last = line;
    }
    line = strtok_r(NULL, "\n", &saveptr);
  }
  if (last)
  {
    snprintf(dst, len, "%s", last);
  }
}

static int runtime_has_active_session(void)
{
  SessionInfo session;
  return select_active_session(&session) == 0;
}

static int runtime_has_notification_tool(void)
{
  char tool_path[PATH_MAX];
  return find_executable("notify-send", tool_path, sizeof(tool_path)) ||
         find_executable("zenity", tool_path, sizeof(tool_path));
}

static int runtime_has_screenshot_tool(void)
{
  char tool_path[PATH_MAX];
  return find_executable("grim", tool_path, sizeof(tool_path)) ||
         find_executable("gnome-screenshot", tool_path, sizeof(tool_path)) ||
         find_executable("xfce4-screenshooter", tool_path, sizeof(tool_path)) ||
         find_executable("scrot", tool_path, sizeof(tool_path)) ||
         find_executable("import", tool_path, sizeof(tool_path));
}

static int runtime_has_active_window_tool(void)
{
  char tool_path[PATH_MAX];
  return find_executable("xdotool", tool_path, sizeof(tool_path)) ||
         find_executable("xprop", tool_path, sizeof(tool_path));
}

static int runtime_has_idle_time_tool(void)
{
  char tool_path[PATH_MAX];
  return find_executable("xprintidle", tool_path, sizeof(tool_path)) || runtime_has_active_session();
}

static int runtime_has_input_control_tool(void)
{
  char tool_path[PATH_MAX];
  return runtime_has_active_session() && find_executable("xinput", tool_path, sizeof(tool_path));
}

static int runtime_has_system_shutdown_tools(void)
{
  char tool_path[PATH_MAX];
  return find_executable("systemctl", tool_path, sizeof(tool_path)) != NULL ||
         find_executable("shutdown", tool_path, sizeof(tool_path)) != NULL;
}

static int runtime_has_network_control_tools(void)
{
  char tool_path[PATH_MAX];
  return find_executable("nft", tool_path, sizeof(tool_path)) != NULL;
}

static int schedule_background_exec(char *const argv[], int delay_seconds)
{
  pid_t pid = fork();
  if (pid < 0)
  {
    return -1;
  }
  if (pid == 0)
  {
    if (delay_seconds > 0)
    {
      sleep((unsigned int)delay_seconds);
    }
    execvp(argv[0], argv);
    _exit(127);
  }
  return 0;
}

static int schedule_background_shell(const char *command, int delay_seconds)
{
  if (!command || !*command)
  {
    return -1;
  }
  pid_t pid = fork();
  if (pid < 0)
  {
    return -1;
  }
  if (pid == 0)
  {
    if (delay_seconds > 0)
    {
      sleep((unsigned int)delay_seconds);
    }
    execl("/bin/sh", "sh", "-lc", command, (char *)NULL);
    _exit(127);
  }
  return 0;
}

static const char *get_allowed_root(void)
{
  const char *root = getenv("QUOODLE_ALLOWED_ROOT");
  if (root && *root)
  {
    return root;
  }
  return "/var/lib/quoodle/data";
}

static int path_is_within(const char *base, const char *path)
{
  if (!base || !path)
  {
    return 0;
  }
  size_t base_len = strlen(base);
  if (strcmp(base, path) == 0)
  {
    return 1;
  }
  return strncmp(base, path, base_len) == 0 && path[base_len] == '/';
}

static int get_allowed_root_real(char *buf, size_t len)
{
  if (!buf || len == 0)
  {
    return -1;
  }
  return realpath(get_allowed_root(), buf) ? 0 : -1;
}

static int runtime_has_allowed_root(void)
{
  char root[PATH_MAX];
  struct stat st;
  if (get_allowed_root_real(root, sizeof(root)) != 0)
  {
    return 0;
  }
  return stat(root, &st) == 0 && S_ISDIR(st.st_mode);
}

static int resolve_under_allowed_root(const char *rel_path, char *resolved, size_t len)
{
  if (!rel_path || !*rel_path || !resolved || len == 0)
  {
    return -1;
  }
  if (rel_path[0] == '/')
  {
    return -1;
  }

  char root[PATH_MAX];
  if (get_allowed_root_real(root, sizeof(root)) != 0)
  {
    return -1;
  }

  char joined[PATH_MAX];
  if (snprintf(joined, sizeof(joined), "%s/%s", root, rel_path) >= (int)sizeof(joined))
  {
    return -1;
  }
  if (!realpath(joined, resolved))
  {
    return errno == ENOENT ? -2 : -1;
  }
  if (!path_is_within(root, resolved))
  {
    return -1;
  }
  return 0;
}

static int relpath_from_allowed_root(const char *full_path, char *rel, size_t len)
{
  if (!full_path || !rel || len == 0)
  {
    return -1;
  }
  char root[PATH_MAX];
  if (get_allowed_root_real(root, sizeof(root)) != 0)
  {
    return -1;
  }
  if (!path_is_within(root, full_path))
  {
    return -1;
  }
  if (strcmp(root, full_path) == 0)
  {
    snprintf(rel, len, ".");
    return 0;
  }
  snprintf(rel, len, "%s", full_path + strlen(root) + 1);
  return 0;
}

static char *base64_encode_alloc(const unsigned char *data, size_t len)
{
  size_t out_len = sodium_base64_ENCODED_LEN(len, sodium_base64_VARIANT_ORIGINAL);
  char *out = (char *)malloc(out_len);
  if (!out)
  {
    return NULL;
  }
  sodium_bin2base64(out, out_len, data, len, sodium_base64_VARIANT_ORIGINAL);
  return out;
}

static unsigned char *base64_decode_alloc(const char *data, size_t *out_len)
{
  if (!data || !out_len)
  {
    return NULL;
  }
  size_t max_len = strlen(data);
  unsigned char *out = (unsigned char *)malloc(max_len ? max_len : 1);
  if (!out)
  {
    return NULL;
  }
  size_t actual_len = 0;
  if (sodium_base642bin(out, max_len, data, strlen(data), NULL, &actual_len, NULL,
                        sodium_base64_VARIANT_ORIGINAL) != 0)
  {
    free(out);
    return NULL;
  }
  *out_len = actual_len;
  return out;
}

static int is_safe_artifact_id(const char *value)
{
  if (!value || !*value)
  {
    return 0;
  }
  for (const unsigned char *p = (const unsigned char *)value; *p; ++p)
  {
    if ((*p >= 'a' && *p <= 'z') ||
        (*p >= 'A' && *p <= 'Z') ||
        (*p >= '0' && *p <= '9') ||
        *p == '-' || *p == '_' || *p == '.')
    {
      continue;
    }
    return 0;
  }
  return 1;
}

static int artifact_path_for_id(const char *artifact_id, char *path, size_t len)
{
  if (!artifact_id || !*artifact_id || !path || len == 0 || !is_safe_artifact_id(artifact_id))
  {
    return -1;
  }
  const char *artifact_dir = get_artifact_dir();
  if (ensure_dir(artifact_dir) != 0)
  {
    return -1;
  }

  char candidate[PATH_MAX];
  snprintf(candidate, sizeof(candidate), "%s/%s", artifact_dir, artifact_id);
  if (access(candidate, R_OK) == 0)
  {
    snprintf(path, len, "%s", candidate);
    return 0;
  }

  snprintf(candidate, sizeof(candidate), "%s/%s.bin", artifact_dir, artifact_id);
  if (access(candidate, R_OK) == 0)
  {
    snprintf(path, len, "%s", candidate);
    return 0;
  }
  return -1;
}

static int resolve_target_under_allowed_root(const char *rel_path, char *resolved, size_t len)
{
  if (!rel_path || !*rel_path || !resolved || len == 0 || rel_path[0] == '/')
  {
    return -1;
  }

  char root[PATH_MAX];
  if (get_allowed_root_real(root, sizeof(root)) != 0)
  {
    return -1;
  }

  char rel_copy[PATH_MAX];
  if (snprintf(rel_copy, sizeof(rel_copy), "%s", rel_path) >= (int)sizeof(rel_copy))
  {
    return -1;
  }

  char *slash = strrchr(rel_copy, '/');
  const char *leaf = rel_copy;
  char parent_rel[PATH_MAX] = ".";
  if (slash)
  {
    *slash = '\0';
    leaf = slash + 1;
    snprintf(parent_rel, sizeof(parent_rel), "%s", *rel_copy ? rel_copy : ".");
  }
  if (!*leaf || strcmp(leaf, ".") == 0 || strcmp(leaf, "..") == 0)
  {
    return -1;
  }

  char parent_joined[PATH_MAX];
  if (snprintf(parent_joined, sizeof(parent_joined), "%s/%s", root, parent_rel) >= (int)sizeof(parent_joined))
  {
    return -1;
  }

  char parent_resolved[PATH_MAX];
  if (!realpath(parent_joined, parent_resolved))
  {
    return errno == ENOENT ? -2 : -1;
  }
  if (!path_is_within(root, parent_resolved))
  {
    return -1;
  }
  if (snprintf(resolved, len, "%s/%s", parent_resolved, leaf) >= (int)len)
  {
    return -1;
  }
  return 0;
}

static int add_list_entries(const char *path, int recursive, int limit, cJSON *entries, int *count)
{
  if (!path || !entries || !count)
  {
    return -1;
  }

  DIR *dir = opendir(path);
  if (!dir)
  {
    return -1;
  }

  struct dirent *entry = NULL;
  int rc = 0;
  while ((entry = readdir(dir)) != NULL && *count < limit)
  {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
    {
      continue;
    }

    char full[PATH_MAX];
    if (snprintf(full, sizeof(full), "%s/%s", path, entry->d_name) >= (int)sizeof(full))
    {
      rc = -1;
      break;
    }

    struct stat st;
    if (lstat(full, &st) != 0)
    {
      continue;
    }

    char rel[PATH_MAX];
    if (relpath_from_allowed_root(full, rel, sizeof(rel)) != 0)
    {
      continue;
    }

    cJSON *item = cJSON_CreateObject();
    cJSON_AddStringToObject(item, "path", rel);
    cJSON_AddBoolToObject(item, "is_dir", S_ISDIR(st.st_mode));
    cJSON_AddNumberToObject(item, "size", (double)st.st_size);
    cJSON_AddNumberToObject(item, "mtime", (double)st.st_mtime);
    cJSON_AddItemToArray(entries, item);
    (*count)++;

    if (recursive && S_ISDIR(st.st_mode) && *count < limit)
    {
      if (add_list_entries(full, recursive, limit, entries, count) != 0)
      {
        rc = -1;
        break;
      }
    }
  }

  closedir(dir);
  return rc;
}

static int search_file_names(const char *path, const char *pattern, int is_regex, regex_t *compiled,
                             int limit, cJSON *matches, int *count)
{
  if (!path || !pattern || !matches || !count)
  {
    return -1;
  }

  DIR *dir = opendir(path);
  if (!dir)
  {
    return -1;
  }

  struct dirent *entry = NULL;
  int rc = 0;
  while ((entry = readdir(dir)) != NULL && *count < limit)
  {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
    {
      continue;
    }

    char full[PATH_MAX];
    if (snprintf(full, sizeof(full), "%s/%s", path, entry->d_name) >= (int)sizeof(full))
    {
      rc = -1;
      break;
    }

    struct stat st;
    if (lstat(full, &st) != 0)
    {
      continue;
    }

    int matched = 0;
    if (is_regex)
    {
      matched = regexec(compiled, entry->d_name, 0, NULL, 0) == 0;
    }
    else
    {
      matched = strstr(entry->d_name, pattern) != NULL;
    }

    if (matched)
    {
      char rel[PATH_MAX];
      if (relpath_from_allowed_root(full, rel, sizeof(rel)) == 0)
      {
        cJSON_AddItemToArray(matches, cJSON_CreateString(rel));
        (*count)++;
      }
    }

    if (S_ISDIR(st.st_mode) && *count < limit)
    {
      if (search_file_names(full, pattern, is_regex, compiled, limit, matches, count) != 0)
      {
        rc = -1;
        break;
      }
    }
  }

  closedir(dir);
  return rc;
}

static int run_cmd_as_user(const char *user, const char *uid_str, char *const argv[])
{
  uid_t uid = 0;
  if (uid_str && *uid_str)
  {
    uid = (uid_t)strtoul(uid_str, NULL, 10);
  }
  struct passwd *pw = uid ? getpwuid(uid) : (user ? getpwnam(user) : NULL);
  if (!pw)
  {
    return -1;
  }

  char dbus_addr[128];
  char runtime_dir[64];
  snprintf(dbus_addr, sizeof(dbus_addr), "unix:path=/run/user/%u/bus", (unsigned)pw->pw_uid);
  snprintf(runtime_dir, sizeof(runtime_dir), "/run/user/%u", (unsigned)pw->pw_uid);

  pid_t pid = fork();
  if (pid < 0)
  {
    return -1;
  }
  if (pid == 0)
  {
    setenv("DBUS_SESSION_BUS_ADDRESS", dbus_addr, 1);
    setenv("XDG_RUNTIME_DIR", runtime_dir, 1);
    if (user)
    {
      initgroups(user, pw->pw_gid);
    }
    setgid(pw->pw_gid);
    setuid(pw->pw_uid);
    execvp(argv[0], argv);
    _exit(127);
  }
  int status = 0;
  if (waitpid(pid, &status, 0) < 0)
  {
    return -1;
  }
  if (WIFEXITED(status))
  {
    return WEXITSTATUS(status);
  }
  return -1;
}

static int fill_session_details(SessionInfo *session)
{
  if (!session || !*session->session)
  {
    return -1;
  }
  char cmd[256];
  snprintf(cmd, sizeof(cmd),
           "loginctl show-session %s -p Active -p State -p Type -p Display -p IdleSinceHintUSec 2>/dev/null",
           session->session);
  char out[1024];
  if (run_cmd_capture(cmd, out, sizeof(out)) != 0)
  {
    return -1;
  }

  char *saveptr = NULL;
  char *line = strtok_r(out, "\n", &saveptr);
  while (line)
  {
    if (strncmp(line, "Active=", 7) == 0)
    {
      session->active = strcmp(line + 7, "yes") == 0;
    }
    else if (strncmp(line, "State=", 6) == 0)
    {
      snprintf(session->state, sizeof(session->state), "%s", line + 6);
    }
    else if (strncmp(line, "Type=", 5) == 0)
    {
      snprintf(session->type, sizeof(session->type), "%s", line + 5);
    }
    else if (strncmp(line, "Display=", 8) == 0)
    {
      snprintf(session->display, sizeof(session->display), "%s", line + 8);
    }
    else if (strncmp(line, "IdleSinceHintUSec=", 18) == 0)
    {
      snprintf(session->idle_usec, sizeof(session->idle_usec), "%s", line + 18);
    }
    line = strtok_r(NULL, "\n", &saveptr);
  }

  return 0;
}

static int select_active_session(SessionInfo *selected)
{
  if (!selected)
  {
    return -1;
  }
  memset(selected, 0, sizeof(*selected));

  FILE *fp = popen("loginctl list-sessions --no-legend", "r");
  if (!fp)
  {
    return -1;
  }

  SessionInfo first = {0};
  int have_first = 0;
  char line[256];
  while (fgets(line, sizeof(line), fp))
  {
    SessionInfo current = {0};
    char seat[64] = {0};
    char tty[64] = {0};
    sscanf(line, "%31s %31s %63s %63s %63s",
           current.session, current.uid, current.user, seat, tty);
    if (!*current.session || !*current.user)
    {
      continue;
    }
    if (fill_session_details(&current) != 0)
    {
      continue;
    }
    if (!have_first)
    {
      first = current;
      have_first = 1;
    }
    if ((current.active || strcmp(current.state, "active") == 0) &&
        (*current.display || strcmp(current.type, "x11") == 0 || strcmp(current.type, "wayland") == 0))
    {
      *selected = current;
      pclose(fp);
      return 0;
    }
  }
  pclose(fp);

  if (have_first)
  {
    *selected = first;
    return 0;
  }
  return -1;
}

static int run_cmd_as_session(const SessionInfo *session, char *const argv[])
{
  if (!session || !*session->user)
  {
    return -1;
  }
  uid_t uid = (uid_t)strtoul(session->uid, NULL, 10);
  struct passwd *pw = getpwuid(uid);
  if (!pw)
  {
    pw = getpwnam(session->user);
  }
  if (!pw)
  {
    return -1;
  }

  char dbus_addr[128];
  char runtime_dir[64];
  char xauthority[PATH_MAX];
  snprintf(dbus_addr, sizeof(dbus_addr), "unix:path=/run/user/%u/bus", (unsigned)pw->pw_uid);
  snprintf(runtime_dir, sizeof(runtime_dir), "/run/user/%u", (unsigned)pw->pw_uid);
  snprintf(xauthority, sizeof(xauthority), "%s/.Xauthority", pw->pw_dir);

  pid_t pid = fork();
  if (pid < 0)
  {
    return -1;
  }
  if (pid == 0)
  {
    setenv("HOME", pw->pw_dir, 1);
    setenv("USER", pw->pw_name, 1);
    setenv("LOGNAME", pw->pw_name, 1);
    setenv("XDG_RUNTIME_DIR", runtime_dir, 1);
    setenv("DBUS_SESSION_BUS_ADDRESS", dbus_addr, 1);
    if (*session->display)
    {
      setenv("DISPLAY", session->display, 1);
    }
    if (access(xauthority, R_OK) == 0)
    {
      setenv("XAUTHORITY", xauthority, 1);
    }
    if (pw->pw_name)
    {
      initgroups(pw->pw_name, pw->pw_gid);
    }
    setgid(pw->pw_gid);
    setuid(pw->pw_uid);
    execvp(argv[0], argv);
    _exit(127);
  }
  int status = 0;
  if (waitpid(pid, &status, 0) < 0)
  {
    return -1;
  }
  if (WIFEXITED(status))
  {
    return WEXITSTATUS(status);
  }
  return -1;
}

static int run_cmd_capture_as_session(const SessionInfo *session, char *const argv[], char *buf, size_t len)
{
  if (!session || !*session->user || !argv || !argv[0] || !buf || len == 0)
  {
    return -1;
  }

  uid_t uid = (uid_t)strtoul(session->uid, NULL, 10);
  struct passwd *pw = getpwuid(uid);
  if (!pw)
  {
    pw = getpwnam(session->user);
  }
  if (!pw)
  {
    return -1;
  }

  int pipefd[2];
  if (pipe(pipefd) != 0)
  {
    return -1;
  }

  char dbus_addr[128];
  char runtime_dir[64];
  char xauthority[PATH_MAX];
  snprintf(dbus_addr, sizeof(dbus_addr), "unix:path=/run/user/%u/bus", (unsigned)pw->pw_uid);
  snprintf(runtime_dir, sizeof(runtime_dir), "/run/user/%u", (unsigned)pw->pw_uid);
  snprintf(xauthority, sizeof(xauthority), "%s/.Xauthority", pw->pw_dir);

  pid_t pid = fork();
  if (pid < 0)
  {
    close(pipefd[0]);
    close(pipefd[1]);
    return -1;
  }
  if (pid == 0)
  {
    dup2(pipefd[1], STDOUT_FILENO);
    dup2(pipefd[1], STDERR_FILENO);
    close(pipefd[0]);
    close(pipefd[1]);
    setenv("HOME", pw->pw_dir, 1);
    setenv("USER", pw->pw_name, 1);
    setenv("LOGNAME", pw->pw_name, 1);
    setenv("XDG_RUNTIME_DIR", runtime_dir, 1);
    setenv("DBUS_SESSION_BUS_ADDRESS", dbus_addr, 1);
    if (*session->display)
    {
      setenv("DISPLAY", session->display, 1);
    }
    if (access(xauthority, R_OK) == 0)
    {
      setenv("XAUTHORITY", xauthority, 1);
    }
    if (pw->pw_name)
    {
      initgroups(pw->pw_name, pw->pw_gid);
    }
    setgid(pw->pw_gid);
    setuid(pw->pw_uid);
    execvp(argv[0], argv);
    _exit(127);
  }

  close(pipefd[1]);
  size_t used = 0;
  buf[0] = '\0';
  ssize_t read_bytes = 0;
  while (used + 1 < len &&
         (read_bytes = read(pipefd[0], buf + used, len - used - 1)) > 0)
  {
    used += (size_t)read_bytes;
  }
  buf[used] = '\0';
  close(pipefd[0]);

  int status = 0;
  if (waitpid(pid, &status, 0) < 0)
  {
    return -1;
  }
  if (WIFEXITED(status))
  {
    return WEXITSTATUS(status);
  }
  return -1;
}

static int lock_sessions_via_loginctl(int *locked_count)
{
  char *const lock_all[] = {"loginctl", "lock-sessions", NULL};
  int rc = run_cmd(lock_all);
  if (rc == 0)
  {
    if (locked_count)
    {
      *locked_count = 1;
    }
    return 0;
  }
  return -1;
}

static int lock_sessions_individual(int *locked_count)
{
  FILE *fp = popen("loginctl list-sessions --no-legend", "r");
  if (!fp)
  {
    return -1;
  }

  int locked = 0;
  char line[256];
  while (fgets(line, sizeof(line), fp))
  {
    char session[32] = {0};
    char uid[32] = {0};
    char user[64] = {0};
    if (sscanf(line, "%31s %31s %63s", session, uid, user) < 2)
    {
      continue;
    }
    char *const argv[] = {"loginctl", "lock-session", session, NULL};
    if (run_cmd(argv) == 0)
    {
      locked++;
    }
  }
  pclose(fp);
  if (locked_count)
  {
    *locked_count = locked;
  }
  return locked > 0 ? 0 : -1;
}

static int lock_sessions_via_qdbus(void)
{
  FILE *fp = popen("loginctl list-sessions --no-legend", "r");
  if (!fp)
  {
    return -1;
  }

  int locked = 0;
  char line[256];
  while (fgets(line, sizeof(line), fp))
  {
    char session[32] = {0};
    char uid[32] = {0};
    char user[64] = {0};
    if (sscanf(line, "%31s %31s %63s", session, uid, user) < 2)
    {
      continue;
    }

    char *const qdbus_args[] = {"qdbus", "org.freedesktop.ScreenSaver", "/ScreenSaver", "Lock", NULL};
    if (run_cmd_as_user(user, uid, qdbus_args) == 0)
    {
      locked++;
      continue;
    }
    char *const qdbus6_args[] = {"qdbus6", "org.freedesktop.ScreenSaver", "/ScreenSaver", "Lock", NULL};
    if (run_cmd_as_user(user, uid, qdbus6_args) == 0)
    {
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
    if (run_cmd_as_user(user, uid, dbus_send_args) == 0)
    {
      locked++;
      continue;
    }
  }
  pclose(fp);
  return locked > 0 ? 0 : -1;
}

static int run_lock_sessions(int *locked_count)
{
  int locked = 0;
  if (lock_sessions_via_loginctl(&locked) == 0)
  {
    if (locked_count)
    {
      *locked_count = locked > 0 ? locked : 1;
    }
    return 0;
  }
  if (lock_sessions_individual(&locked) == 0)
  {
    if (locked_count)
    {
      *locked_count = locked;
    }
    return 0;
  }
  if (lock_sessions_via_qdbus() == 0)
  {
    if (locked_count)
    {
      *locked_count = 1;
    }
    return 0;
  }
  if (locked_count)
  {
    *locked_count = 0;
  }
  return -1;
}

static void strip_quotes(char *value)
{
  if (!value)
  {
    return;
  }
  size_t len = strlen(value);
  if (len >= 2 && value[0] == '"' && value[len - 1] == '"')
  {
    memmove(value, value + 1, len - 2);
    value[len - 2] = '\0';
  }
}

static cJSON *loadavg_object(void)
{
  FILE *fp = fopen("/proc/loadavg", "r");
  cJSON *obj = cJSON_CreateObject();
  if (!fp)
  {
    return obj;
  }

  char one[32] = {0};
  char five[32] = {0};
  char fifteen[32] = {0};
  if (fscanf(fp, "%31s %31s %31s", one, five, fifteen) == 3)
  {
    cJSON_AddStringToObject(obj, "1m", one);
    cJSON_AddStringToObject(obj, "5m", five);
    cJSON_AddStringToObject(obj, "15m", fifteen);
  }
  fclose(fp);
  return obj;
}

static long uptime_seconds(void)
{
  FILE *fp = fopen("/proc/uptime", "r");
  if (!fp)
  {
    return -1;
  }
  double uptime = 0.0;
  int scanned = fscanf(fp, "%lf", &uptime);
  fclose(fp);
  if (scanned != 1)
  {
    return -1;
  }
  return (long)uptime;
}

static cJSON *os_release_object(void)
{
  FILE *fp = fopen("/etc/os-release", "r");
  cJSON *obj = cJSON_CreateObject();
  if (!fp)
  {
    return obj;
  }

  char line[512];
  while (fgets(line, sizeof(line), fp))
  {
    char *eq = strchr(line, '=');
    if (!eq)
    {
      continue;
    }
    *eq = '\0';
    char *key = line;
    char *value = eq + 1;
    char *newline = strchr(value, '\n');
    if (newline)
    {
      *newline = '\0';
    }
    strip_quotes(value);
    if (*key && *value)
    {
      cJSON_AddStringToObject(obj, key, value);
    }
  }
  fclose(fp);
  return obj;
}

static char *handle_sysinfo(void)
{
  cJSON *result = cJSON_CreateObject();
  struct utsname uts;
  if (uname(&uts) == 0)
  {
    cJSON *uname_obj = cJSON_CreateObject();
    cJSON_AddStringToObject(uname_obj, "sysname", uts.sysname);
    cJSON_AddStringToObject(uname_obj, "nodename", uts.nodename);
    cJSON_AddStringToObject(uname_obj, "release", uts.release);
    cJSON_AddStringToObject(uname_obj, "version", uts.version);
    cJSON_AddStringToObject(uname_obj, "machine", uts.machine);
    cJSON_AddItemToObject(result, "uname", uname_obj);
    cJSON_AddStringToObject(result, "hostname", uts.nodename);
  }

  cJSON_AddItemToObject(result, "os_release", os_release_object());

  long uptime = uptime_seconds();
  if (uptime >= 0)
  {
    cJSON_AddNumberToObject(result, "uptime_seconds", uptime);
  }
  else
  {
    cJSON_AddNullToObject(result, "uptime_seconds");
  }

  cJSON_AddItemToObject(result, "loadavg", loadavg_object());

  struct sysinfo info;
  if (sysinfo(&info) == 0)
  {
    cJSON *memory = cJSON_CreateObject();
    unsigned long long unit = info.mem_unit ? (unsigned long long)info.mem_unit : 1ULL;
    cJSON_AddNumberToObject(memory, "total_bytes", (double)((unsigned long long)info.totalram * unit));
    cJSON_AddNumberToObject(memory, "free_bytes", (double)((unsigned long long)info.freeram * unit));
    cJSON_AddNumberToObject(memory, "shared_bytes", (double)((unsigned long long)info.sharedram * unit));
    cJSON_AddNumberToObject(memory, "buffer_bytes", (double)((unsigned long long)info.bufferram * unit));
    cJSON_AddItemToObject(result, "memory", memory);
    cJSON_AddNumberToObject(result, "process_count", info.procs);
  }

  long cpus = sysconf(_SC_NPROCESSORS_ONLN);
  if (cpus > 0)
  {
    cJSON_AddNumberToObject(result, "cpu_count", cpus);
  }

  return build_success(result);
}

static char *handle_health_check(void)
{
  cJSON *result = cJSON_CreateObject();
  char ts[32];
  iso_timestamp(ts, sizeof(ts));
  cJSON_AddBoolToObject(result, "healthy", 1);
  cJSON_AddStringToObject(result, "time", ts);
  cJSON_AddNumberToObject(result, "pid", (double)getpid());

  long uptime = uptime_seconds();
  if (uptime >= 0)
  {
    cJSON_AddNumberToObject(result, "uptime_seconds", uptime);
  }
  else
  {
    cJSON_AddNullToObject(result, "uptime_seconds");
  }

  cJSON_AddItemToObject(result, "loadavg", loadavg_object());
  return build_success(result);
}

static char *handle_logout_sessions(void)
{
  FILE *fp = popen("loginctl list-sessions --no-legend", "r");
  if (!fp)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to enumerate sessions");
  }

  int terminated = 0;
  char line[256];
  while (fgets(line, sizeof(line), fp))
  {
    char session[32] = {0};
    char uid[32] = {0};
    char user[64] = {0};
    if (sscanf(line, "%31s %31s %63s", session, uid, user) < 2)
    {
      continue;
    }
    char *const argv[] = {"loginctl", "terminate-session", session, NULL};
    if (run_cmd(argv) == 0)
    {
      terminated++;
    }
  }
  pclose(fp);

  cJSON *result = cJSON_CreateObject();
  cJSON_AddNumberToObject(result, "session_count_terminated", terminated);
  return build_success(result);
}

static char *handle_get_users(void)
{
  FILE *fp = popen("who", "r");
  if (!fp)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to enumerate users");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON *users = cJSON_CreateArray();
  char line[512];
  while (fgets(line, sizeof(line), fp))
  {
    char user[64] = {0};
    char tty[64] = {0};
    char date[64] = {0};
    char timebuf[64] = {0};
    if (sscanf(line, "%63s %63s %63s %63s", user, tty, date, timebuf) < 2)
    {
      continue;
    }
    cJSON *item = cJSON_CreateObject();
    cJSON_AddStringToObject(item, "user", user);
    cJSON_AddStringToObject(item, "tty", tty);
    if (*date || *timebuf)
    {
      char since[160];
      snprintf(since, sizeof(since), "%s %s", date, timebuf);
      cJSON_AddStringToObject(item, "since", since);
    }
    cJSON_AddItemToArray(users, item);
  }
  pclose(fp);
  cJSON_AddItemToObject(result, "users", users);
  return build_success(result);
}

static cJSON *read_session_details(const char *session_id)
{
  char cmd[256];
  snprintf(cmd, sizeof(cmd),
           "loginctl show-session %s -p Active -p State -p Type -p Display --value 2>/dev/null",
           session_id);
  char out[512];
  if (run_cmd_capture(cmd, out, sizeof(out)) != 0)
  {
    return cJSON_CreateObject();
  }

  cJSON *obj = cJSON_CreateObject();
  char *saveptr = NULL;
  char *line = strtok_r(out, "\n", &saveptr);
  const char *keys[] = {"active", "state", "type", "display"};
  int idx = 0;
  while (line && idx < 4)
  {
    if (idx == 0)
    {
      cJSON_AddBoolToObject(obj, keys[idx], strcmp(line, "yes") == 0);
    }
    else
    {
      cJSON_AddStringToObject(obj, keys[idx], line);
    }
    idx++;
    line = strtok_r(NULL, "\n", &saveptr);
  }
  return obj;
}

static void copy_session_detail(cJSON *target, cJSON *source, const char *key)
{
  cJSON *item = cJSON_GetObjectItem(source, key);
  if (!item)
  {
    return;
  }
  if (cJSON_IsBool(item))
  {
    cJSON_AddBoolToObject(target, key, cJSON_IsTrue(item));
    return;
  }
  if (cJSON_IsString(item) && item->valuestring)
  {
    cJSON_AddStringToObject(target, key, item->valuestring);
  }
}

static char *handle_get_sessions(void)
{
  FILE *fp = popen("loginctl list-sessions --no-legend", "r");
  if (!fp)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to enumerate sessions");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON *sessions = cJSON_CreateArray();
  char line[256];
  while (fgets(line, sizeof(line), fp))
  {
    char session[32] = {0};
    char uid[32] = {0};
    char user[64] = {0};
    char seat[64] = {0};
    char tty[64] = {0};
    sscanf(line, "%31s %31s %63s %63s %63s", session, uid, user, seat, tty);
    if (!*session)
    {
      continue;
    }
    cJSON *item = cJSON_CreateObject();
    cJSON_AddStringToObject(item, "session", session);
    if (*user)
    {
      cJSON_AddStringToObject(item, "user", user);
    }
    if (*uid)
    {
      cJSON_AddStringToObject(item, "uid", uid);
    }
    if (*seat)
    {
      cJSON_AddStringToObject(item, "seat", seat);
    }
    if (*tty)
    {
      cJSON_AddStringToObject(item, "tty", tty);
    }
    cJSON *details = read_session_details(session);
    copy_session_detail(item, details, "active");
    copy_session_detail(item, details, "state");
    copy_session_detail(item, details, "type");
    copy_session_detail(item, details, "display");
    cJSON_Delete(details);
    cJSON_AddItemToArray(sessions, item);
  }
  pclose(fp);
  cJSON_AddItemToObject(result, "sessions", sessions);
  return build_success(result);
}

static char *handle_list_services(void)
{
  FILE *fp = popen("systemctl list-units --type=service --all --no-legend --no-pager", "r");
  if (!fp)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to enumerate services");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON *services = cJSON_CreateArray();
  char line[1024];
  while (fgets(line, sizeof(line), fp))
  {
    char unit[128] = {0};
    char load[32] = {0};
    char active[32] = {0};
    char sub[32] = {0};
    char description[512] = {0};
    if (sscanf(line, "%127s %31s %31s %31s %511[^\n]", unit, load, active, sub, description) < 4)
    {
      continue;
    }
    cJSON *item = cJSON_CreateObject();
    cJSON_AddStringToObject(item, "unit", unit);
    cJSON_AddStringToObject(item, "load", load);
    cJSON_AddStringToObject(item, "active", active);
    cJSON_AddStringToObject(item, "sub", sub);
    if (*description)
    {
      cJSON_AddStringToObject(item, "description", description);
    }
    cJSON_AddItemToArray(services, item);
  }
  pclose(fp);
  cJSON_AddItemToObject(result, "services", services);
  return build_success(result);
}

static char *handle_list_mounts(void)
{
  FILE *fp = fopen("/proc/mounts", "r");
  if (!fp)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to read mounts");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON *mounts = cJSON_CreateArray();
  char source[256];
  char target[256];
  char fstype[64];
  char line[1024];
  while (fgets(line, sizeof(line), fp))
  {
    source[0] = '\0';
    target[0] = '\0';
    fstype[0] = '\0';
    if (sscanf(line, "%255s %255s %63s", source, target, fstype) < 3)
    {
      continue;
    }
    cJSON *item = cJSON_CreateObject();
    cJSON_AddStringToObject(item, "source", source);
    cJSON_AddStringToObject(item, "target", target);
    cJSON_AddStringToObject(item, "fstype", fstype);
    cJSON_AddItemToArray(mounts, item);
  }
  fclose(fp);
  cJSON_AddItemToObject(result, "mounts", mounts);
  return build_success(result);
}

static cJSON *network_interfaces_array(void)
{
  FILE *fp = fopen("/proc/net/dev", "r");
  cJSON *interfaces = cJSON_CreateArray();
  if (!fp)
  {
    return interfaces;
  }
  char line[512];
  int line_no = 0;
  while (fgets(line, sizeof(line), fp))
  {
    line_no++;
    if (line_no <= 2)
    {
      continue;
    }
    char *colon = strchr(line, ':');
    if (!colon)
    {
      continue;
    }
    *colon = '\0';
    char *name = line;
    while (*name && isspace((unsigned char)*name))
    {
      name++;
    }
    char *end = colon - 1;
    while (end > name && isspace((unsigned char)*end))
    {
      *end-- = '\0';
    }
    unsigned long long rx_bytes = 0, rx_packets = 0, tx_bytes = 0, tx_packets = 0;
    if (sscanf(colon + 1,
               " %llu %llu %*u %*u %*u %*u %*u %*u %llu %llu",
               &rx_bytes, &rx_packets, &tx_bytes, &tx_packets) < 4)
    {
      continue;
    }
    cJSON *item = cJSON_CreateObject();
    cJSON_AddStringToObject(item, "name", name);
    cJSON *stats = cJSON_CreateObject();
    cJSON_AddNumberToObject(stats, "rx_bytes", (double)rx_bytes);
    cJSON_AddNumberToObject(stats, "rx_packets", (double)rx_packets);
    cJSON_AddNumberToObject(stats, "tx_bytes", (double)tx_bytes);
    cJSON_AddNumberToObject(stats, "tx_packets", (double)tx_packets);
    cJSON_AddItemToObject(item, "stats", stats);
    cJSON_AddItemToArray(interfaces, item);
  }
  fclose(fp);
  return interfaces;
}

static cJSON *network_routes_array(void)
{
  FILE *fp = fopen("/proc/net/route", "r");
  cJSON *routes = cJSON_CreateArray();
  if (!fp)
  {
    return routes;
  }
  char line[512];
  int line_no = 0;
  while (fgets(line, sizeof(line), fp))
  {
    line_no++;
    if (line_no == 1)
    {
      continue;
    }
    char iface[64] = {0};
    unsigned long destination = 0;
    unsigned long gateway = 0;
    unsigned long mask = 0;
    if (sscanf(line, "%63s %lx %lx %*x %*d %*d %*d %lx", iface, &destination, &gateway, &mask) < 4)
    {
      continue;
    }
    cJSON *item = cJSON_CreateObject();
    cJSON_AddStringToObject(item, "interface", iface);
    cJSON_AddNumberToObject(item, "destination_hex", (double)destination);
    cJSON_AddNumberToObject(item, "gateway_hex", (double)gateway);
    cJSON_AddNumberToObject(item, "mask_hex", (double)mask);
    cJSON_AddItemToArray(routes, item);
  }
  fclose(fp);
  return routes;
}

static char *handle_network_info(void)
{
  cJSON *result = cJSON_CreateObject();
  cJSON_AddItemToObject(result, "interfaces", network_interfaces_array());
  cJSON_AddItemToObject(result, "routes", network_routes_array());
  return build_success(result);
}

static char *handle_env_fingerprint(void)
{
  cJSON *result = cJSON_CreateObject();
  const char *session_type = getenv("XDG_SESSION_TYPE");
  const char *desktop = getenv("XDG_CURRENT_DESKTOP");
  const char *session = getenv("DESKTOP_SESSION");
  cJSON_AddStringToObject(result, "session_type", session_type ? session_type : "");
  cJSON_AddStringToObject(result, "desktop", desktop ? desktop : "");
  cJSON_AddStringToObject(result, "session", session ? session : "");

  FILE *fp = popen("loginctl list-sessions --no-legend", "r");
  if (fp)
  {
    char line[256];
    if (fgets(line, sizeof(line), fp))
    {
      char sess_id[32] = {0};
      char uid[32] = {0};
      char user[64] = {0};
      sscanf(line, "%31s %31s %63s", sess_id, uid, user);
      if (*user)
      {
        cJSON_AddStringToObject(result, "active_user", user);
      }
      cJSON *details = read_session_details(sess_id);
      cJSON *display = cJSON_GetObjectItem(details, "display");
      if (display && cJSON_IsString(display))
      {
        cJSON_AddStringToObject(result, "display", display->valuestring);
      }
      cJSON_Delete(details);
    }
    pclose(fp);
  }

  return build_success(result);
}

static int is_safe_unit_name(const char *unit)
{
  if (!unit || !*unit)
  {
    return 0;
  }
  for (const unsigned char *p = (const unsigned char *)unit; *p; ++p)
  {
    if ((*p >= 'a' && *p <= 'z') ||
        (*p >= 'A' && *p <= 'Z') ||
        (*p >= '0' && *p <= '9') ||
        *p == '-' || *p == '_' || *p == '.')
    {
      continue;
    }
    return 0;
  }
  return 1;
}

static void normalize_unit_name(const char *raw, char *buf, size_t len)
{
  if (!raw || !*raw || !buf || len == 0)
  {
    if (buf && len > 0)
    {
      buf[0] = '\0';
    }
    return;
  }
  if (strchr(raw, '.') == NULL)
  {
    snprintf(buf, len, "%s.service", raw);
    return;
  }
  snprintf(buf, len, "%s", raw);
}

static char *handle_service_action(const char *action, const char *success_key, cJSON *params)
{
  cJSON *unit_item = cJSON_GetObjectItem(params, "unit");
  if (!unit_item || !cJSON_IsString(unit_item) || !unit_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing unit");
  }
  if (!is_safe_unit_name(unit_item->valuestring))
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid unit");
  }

  char unit[160];
  normalize_unit_name(unit_item->valuestring, unit, sizeof(unit));
  char *const argv[] = {"systemctl", (char *)action, unit, NULL};
  if (run_cmd(argv) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "systemctl command failed");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, success_key, 1);
  cJSON_AddStringToObject(result, "unit", unit);
  cJSON_AddStringToObject(result, "action", action);
  return build_success(result);
}

static char *handle_list_connections(cJSON *params)
{
  int limit = 500;
  cJSON *limit_item = cJSON_GetObjectItem(params, "limit");
  if (limit_item && cJSON_IsNumber(limit_item))
  {
    limit = (int)limit_item->valuedouble;
    if (limit < 1)
    {
      limit = 1;
    }
    else if (limit > 500)
    {
      limit = 500;
    }
  }

  FILE *fp = popen("ss -tunapH", "r");
  if (!fp)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to list connections");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON *connections = cJSON_CreateArray();
  char line[2048];
  int count = 0;
  while (count < limit && fgets(line, sizeof(line), fp))
  {
    char *parts[32] = {0};
    int part_count = 0;
    char *saveptr = NULL;
    char *token = strtok_r(line, " \t\r\n", &saveptr);
    while (token && part_count < 32)
    {
      parts[part_count++] = token;
      token = strtok_r(NULL, " \t\r\n", &saveptr);
    }
    if (part_count < 5)
    {
      continue;
    }
    cJSON *item = cJSON_CreateObject();
    cJSON_AddStringToObject(item, "state", parts[0]);
    cJSON_AddStringToObject(item, "local", parts[3]);
    cJSON_AddStringToObject(item, "remote", parts[4]);
    if (part_count > 5)
    {
      char process[1024] = {0};
      size_t used = 0;
      for (int i = 5; i < part_count; ++i)
      {
        int written = snprintf(process + used, sizeof(process) - used, "%s%s",
                               i == 5 ? "" : " ", parts[i]);
        if (written < 0 || (size_t)written >= sizeof(process) - used)
        {
          break;
        }
        used += (size_t)written;
      }
      cJSON_AddStringToObject(item, "process", process);
    }
    else
    {
      cJSON_AddStringToObject(item, "process", "");
    }
    cJSON_AddItemToArray(connections, item);
    count++;
  }
  pclose(fp);
  cJSON_AddItemToObject(result, "connections", connections);
  return build_success(result);
}

static int xinput_devices(const SessionInfo *session, const char *scope, char ids[][16], int max_ids)
{
  if (!session || !ids || max_ids <= 0)
  {
    return 0;
  }
  char xinput_path[PATH_MAX];
  if (!find_executable("xinput", xinput_path, sizeof(xinput_path)))
  {
    return -1;
  }

  char output[8192];
  char *const argv[] = {xinput_path, "list", NULL};
  if (run_cmd_capture_as_session(session, argv, output, sizeof(output)) != 0)
  {
    return -1;
  }

  int count = 0;
  char *saveptr = NULL;
  char *line = strtok_r(output, "\n", &saveptr);
  while (line && count < max_ids)
  {
    char lower[512];
    snprintf(lower, sizeof(lower), "%s", line);
    for (char *p = lower; *p; ++p)
    {
      *p = (char)tolower((unsigned char)*p);
    }
    if (scope && strcmp(scope, "mouse") == 0 &&
        !strstr(lower, "mouse") && !strstr(lower, "pointer"))
    {
      line = strtok_r(NULL, "\n", &saveptr);
      continue;
    }
    if (scope && strcmp(scope, "keyboard") == 0 &&
        !strstr(lower, "keyboard"))
    {
      line = strtok_r(NULL, "\n", &saveptr);
      continue;
    }
    char *id_pos = strstr(line, "id=");
    if (id_pos)
    {
      id_pos += 3;
      int idx = 0;
      while (*id_pos && isdigit((unsigned char)*id_pos) && idx < 15)
      {
        ids[count][idx++] = *id_pos++;
      }
      ids[count][idx] = '\0';
      if (idx > 0)
      {
        count++;
      }
    }
    line = strtok_r(NULL, "\n", &saveptr);
  }
  return count;
}

static char *handle_input_control(cJSON *params, bool enabled)
{
  SessionInfo session;
  if (select_active_session(&session) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "no active session");
  }

  const char *scope = "all";
  cJSON *scope_item = cJSON_GetObjectItem(params, "scope");
  if (scope_item && cJSON_IsString(scope_item) && scope_item->valuestring)
  {
    scope = scope_item->valuestring;
  }

  char ids[64][16];
  int count = xinput_devices(&session, scope, ids, 64);
  if (count < 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "xinput not available");
  }
  if (count == 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "no input devices found");
  }
  char xinput_path[PATH_MAX];
  find_executable("xinput", xinput_path, sizeof(xinput_path));

  for (int i = 0; i < count; ++i)
  {
    char *const argv[] = {xinput_path, enabled ? "enable" : "disable", ids[i], NULL};
    if (run_cmd_as_session(&session, argv) != 0)
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "xinput command failed");
    }
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, "enabled", enabled ? 1 : 0);
  cJSON *devices = cJSON_CreateArray();
  for (int i = 0; i < count; ++i)
  {
    cJSON_AddItemToArray(devices, cJSON_CreateString(ids[i]));
  }
  cJSON_AddItemToObject(result, "devices", devices);
  return build_success(result);
}

static char *handle_show_message(cJSON *params)
{
  SessionInfo session;
  if (select_active_session(&session) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "no active session");
  }

  cJSON *message_item = cJSON_GetObjectItem(params, "message");
  if (!message_item || !cJSON_IsString(message_item) || !message_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing message");
  }

  const char *severity = "info";
  cJSON *severity_item = cJSON_GetObjectItem(params, "severity");
  if (severity_item && cJSON_IsString(severity_item) && severity_item->valuestring)
  {
    severity = severity_item->valuestring;
  }
  int blocking = 0;
  cJSON *blocking_item = cJSON_GetObjectItem(params, "blocking");
  if (blocking_item && cJSON_IsBool(blocking_item))
  {
    blocking = cJSON_IsTrue(blocking_item);
  }

  char tool_path[PATH_MAX];
  int rc = -1;
  if (blocking && find_executable("zenity", tool_path, sizeof(tool_path)))
  {
    char text_arg[512];
    char title_arg[128];
    snprintf(text_arg, sizeof(text_arg), "--text=%s", message_item->valuestring);
    snprintf(title_arg, sizeof(title_arg), "--title=%s", severity);
    char *const argv[] = {tool_path, "--info", text_arg, title_arg, NULL};
    rc = run_cmd_as_session(&session, argv);
  }
  else if (find_executable("notify-send", tool_path, sizeof(tool_path)))
  {
    char *const argv[] = {tool_path, (char *)severity, (char *)message_item->valuestring, NULL};
    rc = run_cmd_as_session(&session, argv);
  }
  if (rc != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "no notification tool available");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, "delivered", 1);
  return build_success(result);
}

static char *handle_screenshot(cJSON *params)
{
  (void)params;
  SessionInfo session;
  if (select_active_session(&session) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "no active session");
  }

  const char *artifact_dir = get_artifact_dir();
  if (ensure_dir(artifact_dir) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "artifact directory unavailable");
  }

  char path[PATH_MAX];
  snprintf(path, sizeof(path), "%s/screenshot-%ld.png", artifact_dir, (long)time(NULL));

  char tool_path[PATH_MAX];
  int rc = -1;
  if (strcmp(session.type, "wayland") == 0 && find_executable("grim", tool_path, sizeof(tool_path)))
  {
    char *const argv[] = {tool_path, path, NULL};
    rc = run_cmd_as_session(&session, argv);
  }
  else if (find_executable("gnome-screenshot", tool_path, sizeof(tool_path)))
  {
    char *const argv[] = {tool_path, "-f", path, NULL};
    rc = run_cmd_as_session(&session, argv);
  }
  else if (find_executable("xfce4-screenshooter", tool_path, sizeof(tool_path)))
  {
    char *const argv[] = {tool_path, "--fullscreen", "--save", path, NULL};
    rc = run_cmd_as_session(&session, argv);
  }
  else if (find_executable("scrot", tool_path, sizeof(tool_path)))
  {
    char *const argv[] = {tool_path, path, NULL};
    rc = run_cmd_as_session(&session, argv);
  }
  else if (find_executable("import", tool_path, sizeof(tool_path)))
  {
    char *const argv[] = {tool_path, "-window", "root", path, NULL};
    rc = run_cmd_as_session(&session, argv);
  }

  if (rc != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "no screenshot tool available");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddStringToObject(result, "path", path);
  const char *base = strrchr(path, '/');
  cJSON_AddStringToObject(result, "artifact_id", base ? base + 1 : path);
  cJSON_AddNullToObject(result, "relative_path");
  return build_success(result);
}

static char *handle_active_window(void)
{
  SessionInfo session;
  if (select_active_session(&session) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "no active session");
  }

  char window_id[256] = {0};
  char title_output[2048] = {0};
  char tool_path[PATH_MAX];

  if (find_executable("xdotool", tool_path, sizeof(tool_path)))
  {
    char raw_window_id[2048] = {0};
    char *const id_argv[] = {tool_path, "getactivewindow", NULL};
    if (run_cmd_capture_as_session(&session, id_argv, raw_window_id, sizeof(raw_window_id)) == 0)
    {
      copy_last_nonempty_line(raw_window_id, window_id, sizeof(window_id));
    }
    char raw_title[2048] = {0};
    char *const title_argv[] = {tool_path, "getactivewindow", "getwindowname", NULL};
    if (run_cmd_capture_as_session(&session, title_argv, raw_title, sizeof(raw_title)) == 0)
    {
      copy_last_nonempty_line(raw_title, title_output, sizeof(title_output));
    }
  }

  if (!*window_id || !*title_output)
  {
    char xprop_path[PATH_MAX];
    if (!find_executable("xprop", xprop_path, sizeof(xprop_path)))
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "active window tools unavailable");
    }

    char output[2048];
    char *const root_argv[] = {xprop_path, "-root", "_NET_ACTIVE_WINDOW", NULL};
    if (run_cmd_capture_as_session(&session, root_argv, output, sizeof(output)) != 0 || !strstr(output, "0x"))
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to get active window");
    }

    char *win_id = strrchr(output, ' ');
    if (!win_id)
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to parse active window");
    }
    while (*win_id == ' ')
    {
      win_id++;
    }
    snprintf(window_id, sizeof(window_id), "%s", win_id);
    trim_trailing_whitespace(window_id);

    char *const title_argv[] = {xprop_path, "-id", window_id, "_NET_WM_NAME", NULL};
    if (run_cmd_capture_as_session(&session, title_argv, title_output, sizeof(title_output)) != 0)
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to get window title");
    }
    char *quoted = strchr(title_output, '"');
    if (quoted)
    {
      quoted++;
      char *end = strrchr(quoted, '"');
      if (end)
      {
        *end = '\0';
      }
      snprintf(title_output, sizeof(title_output), "%s", quoted);
    }
  }
  trim_trailing_whitespace(title_output);

  cJSON *result = cJSON_CreateObject();
  cJSON_AddStringToObject(result, "window_id", window_id);
  cJSON_AddStringToObject(result, "title", title_output);
  return build_success(result);
}

static char *handle_idle_time(void)
{
  SessionInfo session;
  if (select_active_session(&session) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "no active session");
  }

  char tool_path[PATH_MAX];
  if (find_executable("xprintidle", tool_path, sizeof(tool_path)))
  {
    char output[256];
    char *const argv[] = {tool_path, NULL};
    if (run_cmd_capture_as_session(&session, argv, output, sizeof(output)) == 0)
    {
      trim_trailing_whitespace(output);
      int numeric = 1;
      for (char *p = output; *p; ++p)
      {
        if (!isdigit((unsigned char)*p))
        {
          numeric = 0;
          break;
        }
      }
      if (numeric && *output)
      {
        cJSON *result = cJSON_CreateObject();
        cJSON_AddNumberToObject(result, "idle_ms", strtol(output, NULL, 10));
        return build_success(result);
      }
    }
  }

  if (*session.idle_usec == '\0' || strcmp(session.idle_usec, "0") == 0)
  {
    cJSON *result = cJSON_CreateObject();
    cJSON_AddNumberToObject(result, "idle_ms", 0);
    return build_success(result);
  }

  if (*session.idle_usec)
  {
    long long idle_ms = strtoll(session.idle_usec, NULL, 10) / 1000LL;
    cJSON *result = cJSON_CreateObject();
    cJSON_AddNumberToObject(result, "idle_ms", (double)idle_ms);
    return build_success(result);
  }

  return build_failure("ERR_EXECUTION_FAILED", 2001, "idle time unavailable");
}

static char *handle_list_files(cJSON *params)
{
  cJSON *path_item = cJSON_GetObjectItem(params, "path");
  if (!path_item || !cJSON_IsString(path_item) || !path_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing path");
  }

  int limit = 500;
  cJSON *limit_item = cJSON_GetObjectItem(params, "limit");
  if (limit_item && cJSON_IsNumber(limit_item))
  {
    limit = (int)limit_item->valuedouble;
    if (limit < 1)
      limit = 1;
    if (limit > 1000)
      limit = 1000;
  }

  int recursive = 0;
  cJSON *recursive_item = cJSON_GetObjectItem(params, "recursive");
  if (recursive_item && cJSON_IsBool(recursive_item))
  {
    recursive = cJSON_IsTrue(recursive_item);
  }

  char resolved[PATH_MAX];
  int resolve_rc = resolve_under_allowed_root(path_item->valuestring, resolved, sizeof(resolved));
  if (resolve_rc == -2)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path not found");
  }
  if (resolve_rc != 0)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid path");
  }

  struct stat st;
  if (stat(resolved, &st) != 0 || !S_ISDIR(st.st_mode))
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path is not directory");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON *entries = cJSON_CreateArray();
  int count = 0;
  if (add_list_entries(resolved, recursive, limit, entries, &count) != 0)
  {
    cJSON_Delete(entries);
    cJSON_Delete(result);
    return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to list files");
  }
  cJSON_AddItemToObject(result, "entries", entries);
  cJSON_AddNumberToObject(result, "count", count);
  return build_success(result);
}

static char *handle_stat_file(cJSON *params)
{
  cJSON *path_item = cJSON_GetObjectItem(params, "path");
  if (!path_item || !cJSON_IsString(path_item) || !path_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing path");
  }

  char resolved[PATH_MAX];
  int resolve_rc = resolve_under_allowed_root(path_item->valuestring, resolved, sizeof(resolved));
  if (resolve_rc == -2)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path not found");
  }
  if (resolve_rc != 0)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid path");
  }

  struct stat st;
  if (stat(resolved, &st) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "stat failed");
  }

  char rel[PATH_MAX];
  if (relpath_from_allowed_root(resolved, rel, sizeof(rel)) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "relative path failed");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddStringToObject(result, "path", rel);
  cJSON_AddNumberToObject(result, "size", (double)st.st_size);
  cJSON_AddNumberToObject(result, "mtime", (double)st.st_mtime);
  cJSON_AddNumberToObject(result, "mode", (double)st.st_mode);
  cJSON_AddBoolToObject(result, "is_dir", S_ISDIR(st.st_mode));
  return build_success(result);
}

static char *handle_read_file(cJSON *params)
{
  cJSON *path_item = cJSON_GetObjectItem(params, "path");
  if (!path_item || !cJSON_IsString(path_item) || !path_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing path");
  }

  int max_bytes = 1024 * 1024;
  cJSON *max_bytes_item = cJSON_GetObjectItem(params, "max_bytes");
  if (max_bytes_item && cJSON_IsNumber(max_bytes_item))
  {
    max_bytes = (int)max_bytes_item->valuedouble;
    if (max_bytes < 1)
      max_bytes = 1;
    if (max_bytes > 1024 * 1024)
      max_bytes = 1024 * 1024;
  }

  const char *encoding = "utf8";
  cJSON *encoding_item = cJSON_GetObjectItem(params, "encoding");
  if (encoding_item && cJSON_IsString(encoding_item) && encoding_item->valuestring)
  {
    encoding = encoding_item->valuestring;
  }
  if (strcmp(encoding, "utf8") != 0 && strcmp(encoding, "base64") != 0)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid encoding");
  }

  char resolved[PATH_MAX];
  int resolve_rc = resolve_under_allowed_root(path_item->valuestring, resolved, sizeof(resolved));
  if (resolve_rc == -2)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path not found");
  }
  if (resolve_rc != 0)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid path");
  }

  struct stat st;
  if (stat(resolved, &st) != 0 || !S_ISREG(st.st_mode))
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path is not file");
  }

  FILE *fp = fopen(resolved, "rb");
  if (!fp)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "open failed");
  }

  unsigned char *buf = (unsigned char *)malloc((size_t)max_bytes);
  if (!buf)
  {
    fclose(fp);
    return build_failure("ERR_EXECUTION_FAILED", 2001, "allocation failed");
  }
  size_t read_len = fread(buf, 1, (size_t)max_bytes, fp);
  fclose(fp);

  cJSON *result = cJSON_CreateObject();
  cJSON_AddNumberToObject(result, "size", (double)read_len);
  if (strcmp(encoding, "base64") == 0)
  {
    char *data_b64 = base64_encode_alloc(buf, read_len);
    free(buf);
    if (!data_b64)
    {
      cJSON_Delete(result);
      return build_failure("ERR_EXECUTION_FAILED", 2001, "base64 encode failed");
    }
    cJSON_AddStringToObject(result, "data_b64", data_b64);
    free(data_b64);
  }
  else
  {
    char *text = (char *)malloc(read_len + 1);
    if (!text)
    {
      free(buf);
      cJSON_Delete(result);
      return build_failure("ERR_EXECUTION_FAILED", 2001, "allocation failed");
    }
    memcpy(text, buf, read_len);
    text[read_len] = '\0';
    free(buf);
    cJSON_AddStringToObject(result, "data", text);
    free(text);
  }
  return build_success(result);
}

static char *handle_search_files(cJSON *params)
{
  cJSON *path_item = cJSON_GetObjectItem(params, "path");
  cJSON *pattern_item = cJSON_GetObjectItem(params, "pattern");
  if (!path_item || !cJSON_IsString(path_item) || !path_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing path");
  }
  if (!pattern_item || !cJSON_IsString(pattern_item) || !pattern_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing pattern");
  }

  int limit = 200;
  cJSON *limit_item = cJSON_GetObjectItem(params, "limit");
  if (limit_item && cJSON_IsNumber(limit_item))
  {
    limit = (int)limit_item->valuedouble;
    if (limit < 1)
      limit = 1;
    if (limit > 200)
      limit = 200;
  }

  int is_regex = 0;
  cJSON *regex_item = cJSON_GetObjectItem(params, "regex");
  if (regex_item && cJSON_IsBool(regex_item))
  {
    is_regex = cJSON_IsTrue(regex_item);
  }

  char resolved[PATH_MAX];
  int resolve_rc = resolve_under_allowed_root(path_item->valuestring, resolved, sizeof(resolved));
  if (resolve_rc == -2)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path not found");
  }
  if (resolve_rc != 0)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid path");
  }

  struct stat st;
  if (stat(resolved, &st) != 0 || !S_ISDIR(st.st_mode))
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path is not directory");
  }

  regex_t compiled;
  if (is_regex)
  {
    if (regcomp(&compiled, pattern_item->valuestring, REG_EXTENDED | REG_NOSUB) != 0)
    {
      return build_error("ERR_SCHEMA_INVALID", 1001, "invalid regex");
    }
  }

  cJSON *result = cJSON_CreateObject();
  cJSON *matches = cJSON_CreateArray();
  int count = 0;
  int search_rc = search_file_names(resolved, pattern_item->valuestring, is_regex,
                                    is_regex ? &compiled : NULL, limit, matches, &count);
  if (is_regex)
  {
    regfree(&compiled);
  }
  if (search_rc != 0)
  {
    cJSON_Delete(matches);
    cJSON_Delete(result);
    return build_failure("ERR_EXECUTION_FAILED", 2001, "search failed");
  }

  cJSON_AddItemToObject(result, "matches", matches);
  cJSON_AddNumberToObject(result, "count", count);
  return build_success(result);
}

static char *handle_hash_file(cJSON *params)
{
  cJSON *path_item = cJSON_GetObjectItem(params, "path");
  if (!path_item || !cJSON_IsString(path_item) || !path_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing path");
  }

  const char *algo = "sha256";
  cJSON *algo_item = cJSON_GetObjectItem(params, "algo");
  if (algo_item && cJSON_IsString(algo_item) && algo_item->valuestring)
  {
    algo = algo_item->valuestring;
  }

  const char *tool_name = NULL;
  if (strcmp(algo, "sha256") == 0)
  {
    tool_name = "sha256sum";
  }
  else if (strcmp(algo, "sha1") == 0)
  {
    tool_name = "sha1sum";
  }
  else if (strcmp(algo, "md5") == 0)
  {
    tool_name = "md5sum";
  }
  else
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid algo");
  }

  char resolved[PATH_MAX];
  int resolve_rc = resolve_under_allowed_root(path_item->valuestring, resolved, sizeof(resolved));
  if (resolve_rc == -2)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path not found");
  }
  if (resolve_rc != 0)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid path");
  }

  struct stat st;
  if (stat(resolved, &st) != 0 || !S_ISREG(st.st_mode))
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path is not file");
  }

  char tool_path[PATH_MAX];
  if (!find_executable(tool_name, tool_path, sizeof(tool_path)))
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "hash tool unavailable");
  }

  char output[2048];
  char *const argv[] = {tool_path, resolved, NULL};
  if (run_cmd_capture_argv(argv, output, sizeof(output)) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "hash command failed");
  }

  char hash_value[256] = {0};
  if (sscanf(output, "%255s", hash_value) != 1 || !*hash_value)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "invalid hash output");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddStringToObject(result, "hash", hash_value);
  cJSON_AddStringToObject(result, "algo", algo);
  return build_success(result);
}

static char *handle_download_file(cJSON *params)
{
  cJSON *path_item = cJSON_GetObjectItem(params, "path");
  if (!path_item || !cJSON_IsString(path_item) || !path_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing path");
  }

  int max_bytes = 5 * 1024 * 1024;
  cJSON *max_bytes_item = cJSON_GetObjectItem(params, "max_bytes");
  if (max_bytes_item && cJSON_IsNumber(max_bytes_item))
  {
    max_bytes = (int)max_bytes_item->valuedouble;
    if (max_bytes < 1)
      max_bytes = 1;
    if (max_bytes > 5 * 1024 * 1024)
      max_bytes = 5 * 1024 * 1024;
  }

  char resolved[PATH_MAX];
  int resolve_rc = resolve_under_allowed_root(path_item->valuestring, resolved, sizeof(resolved));
  if (resolve_rc == -2)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path not found");
  }
  if (resolve_rc != 0)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid path");
  }

  struct stat st;
  if (stat(resolved, &st) != 0 || !S_ISREG(st.st_mode))
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path is not file");
  }

  FILE *fp = fopen(resolved, "rb");
  if (!fp)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "open failed");
  }

  unsigned char *buf = (unsigned char *)malloc((size_t)max_bytes);
  if (!buf)
  {
    fclose(fp);
    return build_failure("ERR_EXECUTION_FAILED", 2001, "allocation failed");
  }
  size_t read_len = fread(buf, 1, (size_t)max_bytes, fp);
  fclose(fp);

  char *data_b64 = base64_encode_alloc(buf, read_len);
  free(buf);
  if (!data_b64)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "base64 encode failed");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddStringToObject(result, "data_b64", data_b64);
  cJSON_AddNumberToObject(result, "size", (double)read_len);
  free(data_b64);
  return build_success(result);
}

static char *handle_upload_file(cJSON *params)
{
  cJSON *dest_item = cJSON_GetObjectItem(params, "destination");
  if (!dest_item || !cJSON_IsString(dest_item) || !dest_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing destination");
  }

  int overwrite = 0;
  cJSON *overwrite_item = cJSON_GetObjectItem(params, "overwrite");
  if (overwrite_item && cJSON_IsBool(overwrite_item))
  {
    overwrite = cJSON_IsTrue(overwrite_item);
  }

  char dest[PATH_MAX];
  int resolve_rc = resolve_target_under_allowed_root(dest_item->valuestring, dest, sizeof(dest));
  if (resolve_rc == -2)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "destination parent not found");
  }
  if (resolve_rc != 0)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid destination");
  }

  struct stat existing;
  if (stat(dest, &existing) == 0 && !overwrite)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "destination exists");
  }
  if (stat(dest, &existing) == 0 && S_ISDIR(existing.st_mode))
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "destination is directory");
  }

  char parent[PATH_MAX];
  snprintf(parent, sizeof(parent), "%s", dest);
  char *slash = strrchr(parent, '/');
  if (!slash)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid destination");
  }
  *slash = '\0';
  if (ensure_dir(parent) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to prepare destination");
  }

  cJSON *content_item = cJSON_GetObjectItem(params, "content_b64");
  cJSON *artifact_item = cJSON_GetObjectItem(params, "artifact_id");
  if (content_item && cJSON_IsString(content_item) && content_item->valuestring)
  {
    size_t decoded_len = 0;
    unsigned char *decoded = base64_decode_alloc(content_item->valuestring, &decoded_len);
    if (!decoded)
    {
      return build_error("ERR_SCHEMA_INVALID", 1001, "invalid base64 content");
    }
    FILE *fp = fopen(dest, "wb");
    if (!fp)
    {
      free(decoded);
      return build_failure("ERR_EXECUTION_FAILED", 2001, "open failed");
    }
    size_t written = fwrite(decoded, 1, decoded_len, fp);
    fclose(fp);
    free(decoded);
    if (written != decoded_len)
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "write failed");
    }
  }
  else if (artifact_item && cJSON_IsString(artifact_item) && artifact_item->valuestring)
  {
    char artifact_path[PATH_MAX];
    if (artifact_path_for_id(artifact_item->valuestring, artifact_path, sizeof(artifact_path)) != 0)
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "artifact not found");
    }

    FILE *src = fopen(artifact_path, "rb");
    if (!src)
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "artifact open failed");
    }
    FILE *dst = fopen(dest, "wb");
    if (!dst)
    {
      fclose(src);
      return build_failure("ERR_EXECUTION_FAILED", 2001, "open failed");
    }

    unsigned char buf[65536];
    size_t nread = 0;
    int failed = 0;
    while ((nread = fread(buf, 1, sizeof(buf), src)) > 0)
    {
      if (fwrite(buf, 1, nread, dst) != nread)
      {
        failed = 1;
        break;
      }
    }
    fclose(src);
    fclose(dst);
    if (failed)
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "copy failed");
    }
  }
  else
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "content_b64 or artifact_id required");
  }

  char rel[PATH_MAX];
  if (relpath_from_allowed_root(dest, rel, sizeof(rel)) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "relative path failed");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, "written", 1);
  cJSON_AddStringToObject(result, "path", rel);
  return build_success(result);
}

static char *handle_delete_file(cJSON *params)
{
  cJSON *path_item = cJSON_GetObjectItem(params, "path");
  if (!path_item || !cJSON_IsString(path_item) || !path_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing path");
  }

  char resolved[PATH_MAX];
  int resolve_rc = resolve_under_allowed_root(path_item->valuestring, resolved, sizeof(resolved));
  if (resolve_rc == -2)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path not found");
  }
  if (resolve_rc != 0)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid path");
  }

  struct stat st;
  if (lstat(resolved, &st) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "path not found");
  }
  if (S_ISDIR(st.st_mode))
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "refusing to delete directory");
  }
  if (unlink(resolved) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "delete failed");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, "deleted", 1);
  return build_success(result);
}

static char *handle_move_file(cJSON *params)
{
  cJSON *src_item = cJSON_GetObjectItem(params, "src");
  cJSON *dest_item = cJSON_GetObjectItem(params, "dest");
  if (!src_item || !cJSON_IsString(src_item) || !src_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing src");
  }
  if (!dest_item || !cJSON_IsString(dest_item) || !dest_item->valuestring)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing dest");
  }

  int overwrite = 0;
  cJSON *overwrite_item = cJSON_GetObjectItem(params, "overwrite");
  if (overwrite_item && cJSON_IsBool(overwrite_item))
  {
    overwrite = cJSON_IsTrue(overwrite_item);
  }

  char src[PATH_MAX];
  int src_rc = resolve_under_allowed_root(src_item->valuestring, src, sizeof(src));
  if (src_rc == -2)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "src not found");
  }
  if (src_rc != 0)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid src");
  }

  char dest[PATH_MAX];
  int dest_rc = resolve_target_under_allowed_root(dest_item->valuestring, dest, sizeof(dest));
  if (dest_rc == -2)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "destination parent not found");
  }
  if (dest_rc != 0)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid dest");
  }

  struct stat src_st;
  if (lstat(src, &src_st) != 0 || S_ISDIR(src_st.st_mode))
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "src is not file");
  }

  struct stat dest_st;
  if (lstat(dest, &dest_st) == 0)
  {
    if (S_ISDIR(dest_st.st_mode))
    {
      return build_error("ERR_SCHEMA_INVALID", 1001, "dest is directory");
    }
    if (!overwrite)
    {
      return build_error("ERR_SCHEMA_INVALID", 1001, "dest exists");
    }
    if (unlink(dest) != 0)
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to overwrite dest");
    }
  }

  char parent[PATH_MAX];
  snprintf(parent, sizeof(parent), "%s", dest);
  char *slash = strrchr(parent, '/');
  if (!slash)
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "invalid dest");
  }
  *slash = '\0';
  if (ensure_dir(parent) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "unable to prepare destination");
  }

  if (rename(src, dest) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "move failed");
  }

  char rel[PATH_MAX];
  if (relpath_from_allowed_root(dest, rel, sizeof(rel)) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "relative path failed");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, "moved", 1);
  cJSON_AddStringToObject(result, "dest", rel);
  return build_success(result);
}

static char *handle_signal_process(cJSON *params, int sig, const char *flag_name)
{
  cJSON *pid_item = cJSON_GetObjectItem(params, "pid");
  if (!pid_item || !cJSON_IsNumber(pid_item))
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing pid");
  }
  int pid = (int)pid_item->valuedouble;
  if (pid <= 1)
  {
    return build_error("ERR_NOT_AUTHORIZED", 1006, "refusing to signal system process");
  }
  if (kill(pid, sig) != 0)
  {
    if (errno == ESRCH)
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "process not found");
    }
    if (errno == EPERM)
    {
      return build_error("ERR_NOT_AUTHORIZED", 1006, "permission denied");
    }
    return build_failure("ERR_EXECUTION_FAILED", 2001, "signal failed");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, flag_name, 1);
  return build_success(result);
}

static char *handle_power_action(const char *action, cJSON *params)
{
  int delay_seconds = 0;
  cJSON *delay_item = cJSON_GetObjectItem(params, "delay_seconds");
  if (delay_item && cJSON_IsNumber(delay_item))
  {
    delay_seconds = (int)delay_item->valuedouble;
    if (delay_seconds < 0)
    {
      delay_seconds = 0;
    }
    if (delay_seconds > 300)
    {
      delay_seconds = 300;
    }
  }

  char systemctl_path[PATH_MAX];
  char shutdown_path[PATH_MAX];
  int rc = -1;
  if (find_executable("systemctl", systemctl_path, sizeof(systemctl_path)))
  {
    char *const argv[] = {systemctl_path, (char *)action, "--no-wall", NULL};
    rc = schedule_background_exec(argv, delay_seconds > 0 ? delay_seconds : 2);
  }
  else if (find_executable("shutdown", shutdown_path, sizeof(shutdown_path)))
  {
    char *const argv[] = {shutdown_path, strcmp(action, "reboot") == 0 ? "-r" : "-h", "now", NULL};
    rc = schedule_background_exec(argv, delay_seconds > 0 ? delay_seconds : 2);
  }
  if (rc != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "power command unavailable");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, "initiated", 1);
  cJSON_AddBoolToObject(result, strcmp(action, "reboot") == 0 ? "reboot_scheduled" : "shutdown_scheduled", 1);
  cJSON_AddNumberToObject(result, "delay_seconds", delay_seconds > 0 ? delay_seconds : 2);
  return build_success(result);
}

static int nft_apply_rules(const char *table_name, int drop_input, int drop_output)
{
  char nft_path[PATH_MAX];
  if (!find_executable("nft", nft_path, sizeof(nft_path)))
  {
    return -1;
  }

  char table_spec[128];
  snprintf(table_spec, sizeof(table_spec), "inet %s", table_name);
  char input_chain[512];
  char output_chain[512];
  snprintf(input_chain, sizeof(input_chain),
           "type filter hook input priority -150; policy accept; %s %s",
           "iif lo accept;",
           drop_input ? "counter drop;" : "");
  snprintf(output_chain, sizeof(output_chain),
           "type filter hook output priority -150; policy accept; %s %s",
           "oif lo accept;",
           drop_output ? "counter drop;" : "");

  char *const delete_argv[] = {nft_path, "delete", "table", "inet", (char *)table_name, NULL};
  run_cmd(delete_argv);

  char *const add_table_argv[] = {nft_path, "add", "table", "inet", (char *)table_name, NULL};
  if (run_cmd(add_table_argv) != 0)
  {
    return -1;
  }
  char *const add_input_argv[] = {nft_path, "add", "chain", "inet", (char *)table_name, "input",
                                  "{", input_chain, "}", NULL};
  if (run_cmd(add_input_argv) != 0)
  {
    return -1;
  }
  char *const add_output_argv[] = {nft_path, "add", "chain", "inet", (char *)table_name, "output",
                                   "{", output_chain, "}", NULL};
  if (run_cmd(add_output_argv) != 0)
  {
    return -1;
  }
  return 0;
}

static int nft_clear_table(const char *table_name)
{
  char nft_path[PATH_MAX];
  if (!find_executable("nft", nft_path, sizeof(nft_path)))
  {
    return -1;
  }
  char *const argv[] = {nft_path, "delete", "table", "inet", (char *)table_name, NULL};
  int rc = run_cmd(argv);
  if (rc == 0)
  {
    return 0;
  }
  return 0;
}

static char *handle_network_disconnect(cJSON *params)
{
  int duration_seconds = 0;
  cJSON *duration_item = cJSON_GetObjectItem(params, "duration_seconds");
  if (duration_item && cJSON_IsNumber(duration_item))
  {
    duration_seconds = (int)duration_item->valuedouble;
    if (duration_seconds < 0)
      duration_seconds = 0;
    if (duration_seconds > 600)
      duration_seconds = 600;
  }

  char command[2048];
  snprintf(command, sizeof(command),
           "nft delete table inet quoodle_disconnect 2>/dev/null || true; "
           "nft add table inet quoodle_disconnect && "
           "nft add chain inet quoodle_disconnect input '{ type filter hook input priority -150; policy accept; iif lo accept; counter drop; }' && "
           "nft add chain inet quoodle_disconnect output '{ type filter hook output priority -150; policy accept; oif lo accept; counter drop; }'%s",
           duration_seconds > 0 ? "; sleep PLACEHOLDER; nft delete table inet quoodle_disconnect 2>/dev/null || true" : "");
  if (duration_seconds > 0)
  {
    char duration_cmd[2048];
    snprintf(duration_cmd, sizeof(duration_cmd),
             "nft delete table inet quoodle_disconnect 2>/dev/null || true; "
             "nft add table inet quoodle_disconnect && "
             "nft add chain inet quoodle_disconnect input '{ type filter hook input priority -150; policy accept; iif lo accept; counter drop; }' && "
             "nft add chain inet quoodle_disconnect output '{ type filter hook output priority -150; policy accept; oif lo accept; counter drop; }'; "
             "sleep %d; nft delete table inet quoodle_disconnect 2>/dev/null || true",
             duration_seconds);
    if (schedule_background_shell(duration_cmd, 2) != 0)
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "failed to schedule disconnect rules");
    }
  }
  else if (schedule_background_shell(command, 2) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "failed to schedule disconnect rules");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, "isolated", 1);
  cJSON_AddNumberToObject(result, "delay_seconds", 2);
  if (duration_seconds > 0)
  {
    cJSON_AddNumberToObject(result, "duration_seconds", duration_seconds);
  }
  return build_success(result);
}

static char *handle_network_reconnect(void)
{
  if (nft_clear_table("quoodle_disconnect") != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "failed to clear disconnect rules");
  }
  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, "isolated", 0);
  return build_success(result);
}

static char *handle_block_outbound(cJSON *params)
{
  int duration_seconds = 0;
  cJSON *duration_item = cJSON_GetObjectItem(params, "duration_seconds");
  if (duration_item && cJSON_IsNumber(duration_item))
  {
    duration_seconds = (int)duration_item->valuedouble;
    if (duration_seconds < 0)
      duration_seconds = 0;
    if (duration_seconds > 3600)
      duration_seconds = 3600;
  }

  char command[2048];
  snprintf(command, sizeof(command),
           "nft delete table inet quoodle_outbound 2>/dev/null || true; "
           "nft add table inet quoodle_outbound && "
           "nft add chain inet quoodle_outbound input '{ type filter hook input priority -150; policy accept; }' && "
           "nft add chain inet quoodle_outbound output '{ type filter hook output priority -150; policy accept; oif lo accept; counter drop; }'%s",
           duration_seconds > 0 ? "; sleep PLACEHOLDER; nft delete table inet quoodle_outbound 2>/dev/null || true" : "");
  if (duration_seconds > 0)
  {
    char duration_cmd[2048];
    snprintf(duration_cmd, sizeof(duration_cmd),
             "nft delete table inet quoodle_outbound 2>/dev/null || true; "
             "nft add table inet quoodle_outbound && "
             "nft add chain inet quoodle_outbound input '{ type filter hook input priority -150; policy accept; }' && "
             "nft add chain inet quoodle_outbound output '{ type filter hook output priority -150; policy accept; oif lo accept; counter drop; }'; "
             "sleep %d; nft delete table inet quoodle_outbound 2>/dev/null || true",
             duration_seconds);
    if (schedule_background_shell(duration_cmd, 2) != 0)
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "failed to schedule outbound rules");
    }
  }
  else if (schedule_background_shell(command, 2) != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "failed to schedule outbound rules");
  }

  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, "outbound_blocked", 1);
  cJSON_AddNumberToObject(result, "delay_seconds", 2);
  if (duration_seconds > 0)
  {
    cJSON_AddNumberToObject(result, "duration_seconds", duration_seconds);
  }
  return build_success(result);
}

static char *handle_allow_outbound(void)
{
  if (nft_clear_table("quoodle_outbound") != 0)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "failed to clear outbound rules");
  }
  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, "outbound_blocked", 0);
  return build_success(result);
}

static char *handle_kill_process(cJSON *params)
{
  cJSON *pid_item = cJSON_GetObjectItem(params, "pid");
  if (!pid_item || !cJSON_IsNumber(pid_item))
  {
    return build_error("ERR_SCHEMA_INVALID", 1001, "missing pid");
  }
  int pid = (int)pid_item->valuedouble;
  if (pid <= 1)
  {
    return build_error("ERR_NOT_AUTHORIZED", 1006, "refusing to terminate system process");
  }

  int sig = SIGTERM;
  cJSON *sig_item = cJSON_GetObjectItem(params, "signal");
  if (sig_item)
  {
    if (!cJSON_IsNumber(sig_item))
    {
      return build_error("ERR_SCHEMA_INVALID", 1001, "invalid signal");
    }
    sig = (int)sig_item->valuedouble;
    if (sig <= 0 || sig > 64)
    {
      return build_error("ERR_SCHEMA_INVALID", 1001, "invalid signal");
    }
  }

  if (kill(pid, sig) != 0)
  {
    if (errno == ESRCH)
    {
      return build_failure("ERR_EXECUTION_FAILED", 2001, "process not found");
    }
    if (errno == EPERM)
    {
      return build_error("ERR_NOT_AUTHORIZED", 1006, "permission denied");
    }
    return build_failure("ERR_EXECUTION_FAILED", 2001, "kill failed");
  }

  cJSON *resp = cJSON_CreateObject();
  cJSON_AddStringToObject(resp, "status", "ok");
  cJSON *result = cJSON_CreateObject();
  cJSON_AddBoolToObject(result, "killed", 1);
  cJSON_AddItemToObject(resp, "result", result);
  char *out = dup_json(resp);
  cJSON_Delete(resp);
  return out;
}

static int read_first_line(const char *path, char *buf, size_t len)
{
  FILE *fp = fopen(path, "r");
  if (!fp)
  {
    return -1;
  }
  if (!fgets(buf, (int)len, fp))
  {
    fclose(fp);
    return -1;
  }
  fclose(fp);
  size_t blen = strlen(buf);
  while (blen > 0 && (buf[blen - 1] == '\n' || buf[blen - 1] == '\r'))
  {
    buf[--blen] = '\0';
  }
  return 0;
}

static int parse_uid_from_status(const char *path, uid_t *uid_out)
{
  FILE *fp = fopen(path, "r");
  if (!fp)
  {
    return -1;
  }
  char line[256];
  while (fgets(line, sizeof(line), fp))
  {
    if (strncmp(line, "Uid:", 4) == 0)
    {
      unsigned int uid = 0;
      if (sscanf(line, "Uid:\t%u", &uid) == 1)
      {
        *uid_out = (uid_t)uid;
        fclose(fp);
        return 0;
      }
    }
  }
  fclose(fp);
  return -1;
}

static char *handle_list_processes(cJSON *params)
{
  int limit = 100;
  const char *user_filter = NULL;
  const char *name_filter = NULL;

  if (params)
  {
    cJSON *limit_item = cJSON_GetObjectItem(params, "limit");
    if (limit_item && cJSON_IsNumber(limit_item))
    {
      limit = (int)limit_item->valuedouble;
      if (limit < 1)
        limit = 1;
      if (limit > 500)
        limit = 500;
    }
    cJSON *user_item = cJSON_GetObjectItem(params, "user");
    if (user_item && cJSON_IsString(user_item))
    {
      user_filter = user_item->valuestring;
    }
    cJSON *name_item = cJSON_GetObjectItem(params, "name");
    if (name_item && cJSON_IsString(name_item))
    {
      name_filter = name_item->valuestring;
    }
  }

  DIR *dir = opendir("/proc");
  if (!dir)
  {
    return build_failure("ERR_EXECUTION_FAILED", 2001, "failed to open /proc");
  }

  cJSON *resp = cJSON_CreateObject();
  cJSON_AddStringToObject(resp, "status", "ok");
  cJSON *result = cJSON_CreateObject();
  cJSON *items = cJSON_CreateArray();
  cJSON_AddItemToObject(result, "processes", items);

  struct dirent *entry;
  int count = 0;
  while ((entry = readdir(dir)) != NULL && count < limit)
  {
    const char *name = entry->d_name;
    if (!isdigit((unsigned char)name[0]))
    {
      continue;
    }
    char *endptr = NULL;
    long pid = strtol(name, &endptr, 10);
    if (!endptr || *endptr != '\0' || pid <= 0)
    {
      continue;
    }

    char comm_path[256];
    snprintf(comm_path, sizeof(comm_path), "/proc/%ld/comm", pid);
    char comm[128];
    if (read_first_line(comm_path, comm, sizeof(comm)) != 0)
    {
      continue;
    }
    if (name_filter && *name_filter)
    {
      if (strstr(comm, name_filter) == NULL)
      {
        continue;
      }
    }

    uid_t uid = 0;
    char status_path[256];
    snprintf(status_path, sizeof(status_path), "/proc/%ld/status", pid);
    if (parse_uid_from_status(status_path, &uid) != 0)
    {
      continue;
    }
    struct passwd *pw = getpwuid(uid);
    const char *user = pw ? pw->pw_name : NULL;
    if (user_filter && *user_filter)
    {
      if (!user || strcmp(user, user_filter) != 0)
      {
        continue;
      }
    }

    cJSON *item = cJSON_CreateObject();
    cJSON_AddNumberToObject(item, "pid", pid);
    cJSON_AddStringToObject(item, "name", comm);
    if (user)
    {
      cJSON_AddStringToObject(item, "user", user);
    }
    cJSON_AddItemToArray(items, item);
    count++;
  }
  closedir(dir);

  cJSON_AddNumberToObject(result, "count", count);
  cJSON_AddItemToObject(resp, "result", result);

  char *out = dup_json(resp);
  cJSON_Delete(resp);
  return out;
}

int executor_handle_request(const char *json_request, char **json_response)
{
  if (!json_request || !json_response)
  {
    return -1;
  }

  cJSON *root = cJSON_Parse(json_request);
  if (!root)
  {
    *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "invalid JSON");
    return *json_response ? 0 : -1;
  }

  const cJSON *cap = cJSON_GetObjectItem(root, "capability");
  cJSON *params = cJSON_GetObjectItem(root, "params");
  if (!cap || !cJSON_IsString(cap) || !cap->valuestring)
  {
    cJSON_Delete(root);
    *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing capability");
    return *json_response ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_LOCK_SESSION") == 0)
  {
    int locked = 0;
    int rc = run_lock_sessions(&locked);
    if (rc != 0)
    {
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

  if (strcmp(cap->valuestring, "CAP_LOGOUT_SESSION") == 0)
  {
    char *out = handle_logout_sessions();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_TERMINATE_PROCESS") == 0)
  {
    if (!params || !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_kill_process(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_LIST_PROCESSES") == 0)
  {
    if (params && !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "invalid params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_list_processes(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_SYSINFO") == 0)
  {
    char *out = handle_sysinfo();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_HEALTH_CHECK") == 0)
  {
    char *out = handle_health_check();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_GET_USERS") == 0)
  {
    char *out = handle_get_users();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_GET_SESSIONS") == 0)
  {
    char *out = handle_get_sessions();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_LIST_SERVICES") == 0)
  {
    char *out = handle_list_services();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_NETWORK_INFO") == 0)
  {
    char *out = handle_network_info();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_LIST_MOUNTS") == 0)
  {
    char *out = handle_list_mounts();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_ENV_FINGERPRINT") == 0)
  {
    char *out = handle_env_fingerprint();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_FS_LIST") == 0)
  {
    if (!params || !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_list_files(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_FS_STAT") == 0)
  {
    if (!params || !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_stat_file(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_FS_READ") == 0)
  {
    if (!params || !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_read_file(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_FS_SEARCH") == 0)
  {
    if (!params || !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_search_files(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_FS_HASH") == 0)
  {
    if (!params || !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_hash_file(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_FS_DOWNLOAD") == 0)
  {
    if (!params || !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_download_file(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_FS_UPLOAD") == 0)
  {
    if (!params || !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_upload_file(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_FS_DELETE") == 0)
  {
    if (!params || !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_delete_file(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_FS_MOVE") == 0)
  {
    if (!params || !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_move_file(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_REBOOT_SYSTEM") == 0)
  {
    if (params && !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "invalid params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_power_action("reboot", params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_SHUTDOWN_SYSTEM") == 0)
  {
    if (params && !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "invalid params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_power_action("poweroff", params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_PAUSE_PROCESS") == 0)
  {
    if (!params || !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_signal_process(params, SIGSTOP, "paused");
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_RESUME_PROCESS") == 0)
  {
    if (!params || !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "missing params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_signal_process(params, SIGCONT, "resumed");
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_SERVICE_START") == 0)
  {
    char *out = handle_service_action("start", "started", params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_SERVICE_STOP") == 0)
  {
    char *out = handle_service_action("stop", "stopped", params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_SERVICE_RESTART") == 0)
  {
    char *out = handle_service_action("restart", "restarted", params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_NETWORK_DISCONNECT") == 0)
  {
    if (params && !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "invalid params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_network_disconnect(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_NETWORK_RECONNECT") == 0)
  {
    if (params && !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "invalid params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_network_reconnect();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_NETWORK_ISOLATION") == 0)
  {
    if (params && !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "invalid params");
      return *json_response ? 0 : -1;
    }
    int enabled = 1;
    if (params)
    {
      cJSON *enabled_item = cJSON_GetObjectItem(params, "enabled");
      if (enabled_item && cJSON_IsBool(enabled_item))
      {
        enabled = cJSON_IsTrue(enabled_item);
      }
    }
    char *out = enabled ? handle_network_disconnect(params) : handle_network_reconnect();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_LIST_CONNECTIONS") == 0)
  {
    char *out = handle_list_connections(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_BLOCK_OUTBOUND") == 0)
  {
    if (params && !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "invalid params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_block_outbound(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_ALLOW_OUTBOUND") == 0)
  {
    if (params && !cJSON_IsObject(params))
    {
      cJSON_Delete(root);
      *json_response = build_error("ERR_SCHEMA_INVALID", 1001, "invalid params");
      return *json_response ? 0 : -1;
    }
    char *out = handle_allow_outbound();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_INPUT_CONTROL") == 0)
  {
    cJSON *enabled_item = cJSON_GetObjectItem(params, "enabled");
    int enabled = enabled_item && cJSON_IsBool(enabled_item) && cJSON_IsTrue(enabled_item);
    char *out = handle_input_control(params, enabled);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_SHOW_MESSAGE") == 0)
  {
    char *out = handle_show_message(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_SCREENSHOT") == 0)
  {
    char *out = handle_screenshot(params);
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_ACTIVE_WINDOW") == 0)
  {
    char *out = handle_active_window();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_IDLE_TIME") == 0)
  {
    char *out = handle_idle_time();
    cJSON_Delete(root);
    *json_response = out;
    return out ? 0 : -1;
  }

  if (strcmp(cap->valuestring, "CAP_DISCOVERY") == 0)
  {
    cJSON *resp = cJSON_CreateObject();
    cJSON_AddStringToObject(resp, "status", "ok");
    cJSON *result = cJSON_CreateObject();
    cJSON *caps = cJSON_CreateArray();
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_LOCK_SESSION"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_TERMINATE_PROCESS"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_LIST_PROCESSES"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_LOGOUT_SESSION"));
    if (runtime_has_system_shutdown_tools())
    {
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_REBOOT_SYSTEM"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_SHUTDOWN_SYSTEM"));
    }
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_SYSINFO"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_HEALTH_CHECK"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_GET_USERS"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_GET_SESSIONS"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_LIST_SERVICES"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_NETWORK_INFO"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_LIST_MOUNTS"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_ENV_FINGERPRINT"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_PAUSE_PROCESS"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_RESUME_PROCESS"));
    if (runtime_has_allowed_root())
    {
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_FS_LIST"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_FS_STAT"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_FS_READ"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_FS_SEARCH"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_FS_HASH"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_FS_DOWNLOAD"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_FS_UPLOAD"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_FS_DELETE"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_FS_MOVE"));
    }
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_SERVICE_START"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_SERVICE_STOP"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_SERVICE_RESTART"));
    cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_LIST_CONNECTIONS"));
    if (runtime_has_network_control_tools())
    {
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_NETWORK_DISCONNECT"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_NETWORK_RECONNECT"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_NETWORK_ISOLATION"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_BLOCK_OUTBOUND"));
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_ALLOW_OUTBOUND"));
    }
    if (runtime_has_input_control_tool())
    {
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_INPUT_CONTROL"));
    }
    if (runtime_has_notification_tool() && runtime_has_active_session())
    {
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_SHOW_MESSAGE"));
    }
    if (runtime_has_screenshot_tool() && runtime_has_active_session())
    {
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_SCREENSHOT"));
    }
    if (runtime_has_active_window_tool() && runtime_has_active_session())
    {
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_ACTIVE_WINDOW"));
    }
    if (runtime_has_idle_time_tool())
    {
      cJSON_AddItemToArray(caps, cJSON_CreateString("CAP_IDLE_TIME"));
    }
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
