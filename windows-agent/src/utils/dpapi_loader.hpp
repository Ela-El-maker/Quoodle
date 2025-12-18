#pragma once

#ifdef _WIN32
#include <string>
bool dpapi_load_blob_to_b64(const char *env_var, const char *path_env, std::string &out_b64);
#else
inline bool dpapi_load_blob_to_b64(const char *, const char *, std::string &)
{
    return false;
}
#endif
