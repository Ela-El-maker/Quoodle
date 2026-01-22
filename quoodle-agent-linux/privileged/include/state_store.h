#pragma once

int state_store_load_sequence(const char *device_id, long *last_seq);
int state_store_save_sequence(const char *device_id, long seq);
int state_store_get_response(const char *request_id, char **json_response_out);
int state_store_save_response(const char *request_id, const char *json_response);
