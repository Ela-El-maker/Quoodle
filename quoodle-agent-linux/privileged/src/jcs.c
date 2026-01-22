#include "jcs.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"

typedef struct {
    char *data;
    size_t len;
    size_t cap;
} sbuf_t;

static int sbuf_grow(sbuf_t *buf, size_t extra) {
    if (buf->len + extra + 1 <= buf->cap) {
        return 0;
    }
    size_t next = buf->cap ? buf->cap * 2 : 256;
    while (next < buf->len + extra + 1) {
        next *= 2;
    }
    char *tmp = (char *)realloc(buf->data, next);
    if (!tmp) {
        return -1;
    }
    buf->data = tmp;
    buf->cap = next;
    return 0;
}

static int sbuf_append(sbuf_t *buf, const char *text, size_t len) {
    if (sbuf_grow(buf, len) != 0) {
        return -1;
    }
    memcpy(buf->data + buf->len, text, len);
    buf->len += len;
    buf->data[buf->len] = '\0';
    return 0;
}

static int sbuf_append_char(sbuf_t *buf, char c) {
    return sbuf_append(buf, &c, 1);
}

static int append_json_string(sbuf_t *buf, const char *value) {
    if (sbuf_append_char(buf, '\"') != 0) {
        return -1;
    }
    for (const unsigned char *p = (const unsigned char *)value; *p; ++p) {
        unsigned char ch = *p;
        switch (ch) {
            case '\"':
                if (sbuf_append(buf, "\\\"", 2) != 0) return -1;
                break;
            case '\\':
                if (sbuf_append(buf, "\\\\", 2) != 0) return -1;
                break;
            case '\b':
                if (sbuf_append(buf, "\\b", 2) != 0) return -1;
                break;
            case '\f':
                if (sbuf_append(buf, "\\f", 2) != 0) return -1;
                break;
            case '\n':
                if (sbuf_append(buf, "\\n", 2) != 0) return -1;
                break;
            case '\r':
                if (sbuf_append(buf, "\\r", 2) != 0) return -1;
                break;
            case '\t':
                if (sbuf_append(buf, "\\t", 2) != 0) return -1;
                break;
            default:
                if (ch < 0x20) {
                    char tmp[7];
                    snprintf(tmp, sizeof(tmp), "\\u%04x", ch);
                    if (sbuf_append(buf, tmp, strlen(tmp)) != 0) return -1;
                } else {
                    if (sbuf_append_char(buf, (char)ch) != 0) return -1;
                }
                break;
        }
    }
    return sbuf_append_char(buf, '\"');
}

static int render_value(sbuf_t *buf, cJSON *item);

static int render_array(sbuf_t *buf, cJSON *item) {
    if (sbuf_append_char(buf, '[') != 0) return -1;
    cJSON *child = item->child;
    int first = 1;
    while (child) {
        if (!first && sbuf_append_char(buf, ',') != 0) return -1;
        if (render_value(buf, child) != 0) return -1;
        first = 0;
        child = child->next;
    }
    return sbuf_append_char(buf, ']');
}

static int compare_keys(const void *a, const void *b) {
    const cJSON *ia = *(const cJSON **)a;
    const cJSON *ib = *(const cJSON **)b;
    return strcmp(ia->string, ib->string);
}

static int render_object(sbuf_t *buf, cJSON *item) {
    if (sbuf_append_char(buf, '{') != 0) return -1;

    size_t count = 0;
    for (cJSON *child = item->child; child; child = child->next) {
        count++;
    }
    cJSON **items = (cJSON **)calloc(count, sizeof(cJSON *));
    if (!items) return -1;
    size_t idx = 0;
    for (cJSON *child = item->child; child; child = child->next) {
        items[idx++] = child;
    }
    qsort(items, count, sizeof(cJSON *), compare_keys);

    int first = 1;
    for (size_t i = 0; i < count; ++i) {
        cJSON *child = items[i];
        if (!first && sbuf_append_char(buf, ',') != 0) {
            free(items);
            return -1;
        }
        if (append_json_string(buf, child->string) != 0) {
            free(items);
            return -1;
        }
        if (sbuf_append_char(buf, ':') != 0) {
            free(items);
            return -1;
        }
        if (render_value(buf, child) != 0) {
            free(items);
            return -1;
        }
        first = 0;
    }
    free(items);
    return sbuf_append_char(buf, '}');
}

static int render_number(sbuf_t *buf, cJSON *item) {
    double val = item->valuedouble;
    double rounded = floor(val + 0.5);
    if (fabs(val - rounded) > 1e-9) {
        return -1;
    }
    char tmp[64];
    long long int_val = (long long)rounded;
    snprintf(tmp, sizeof(tmp), "%lld", int_val);
    return sbuf_append(buf, tmp, strlen(tmp));
}

static int render_value(sbuf_t *buf, cJSON *item) {
    if (cJSON_IsNull(item)) {
        return sbuf_append(buf, "null", 4);
    }
    if (cJSON_IsTrue(item)) {
        return sbuf_append(buf, "true", 4);
    }
    if (cJSON_IsFalse(item)) {
        return sbuf_append(buf, "false", 5);
    }
    if (cJSON_IsNumber(item)) {
        return render_number(buf, item);
    }
    if (cJSON_IsString(item)) {
        return append_json_string(buf, item->valuestring ? item->valuestring : "");
    }
    if (cJSON_IsArray(item)) {
        return render_array(buf, item);
    }
    if (cJSON_IsObject(item)) {
        return render_object(buf, item);
    }
    return -1;
}

int jcs_canonicalize(const char *json_in, char **json_out) {
    if (!json_in || !json_out) {
        return -1;
    }
    cJSON *root = cJSON_Parse(json_in);
    if (!root) {
        return -1;
    }

    sbuf_t buf = {0};
    if (render_value(&buf, root) != 0) {
        cJSON_Delete(root);
        free(buf.data);
        return -1;
    }

    *json_out = buf.data;
    cJSON_Delete(root);
    return 0;
}
