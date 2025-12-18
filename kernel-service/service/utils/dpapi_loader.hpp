#pragma once

#ifdef _WIN32
#include <string>
#include <windows.h>

// Try to load a DPAPI-protected base64 blob either from env (env_var)
// or from a file path (path_env). On success returns true and fills out_b64
// with a base64 string of the unprotected data (raw bytes -> base64).
bool dpapi_load_blob_to_b64(const char *env_var, const char *path_env, std::string &out_b64);

#else
// Non-Windows stub
inline bool dpapi_load_blob_to_b64(const char *, const char *, std::string &)
{
    (void)0;
    return false;
}
#endif
