#include "dpapi_loader.hpp"
#ifdef _WIN32
#include <windows.h>
#include <wincrypt.h>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>

static bool read_file(const char *path, std::string &out)
{
    if (!path)
        return false;
    std::ifstream ifs(path, std::ios::binary);
    if (!ifs)
        return false;
    std::ostringstream ss;
    ss << ifs.rdbuf();
    out = ss.str();
    return true;
}

// Helper: convert base64 string to bytes using CryptStringToBinaryA
static bool base64_to_bin(const std::string &b64, std::vector<BYTE> &out)
{
    DWORD needed = 0;
    if (!CryptStringToBinaryA(b64.c_str(), (DWORD)b64.size(), CRYPT_STRING_BASE64, NULL, &needed, NULL, NULL))
        return false;
    out.resize(needed);
    if (!CryptStringToBinaryA(b64.c_str(), (DWORD)b64.size(), CRYPT_STRING_BASE64, out.data(), &needed, NULL, NULL))
        return false;
    out.resize(needed);
    return true;
}

// Helper: convert binary to base64 using CryptBinaryToStringA
static bool bin_to_base64(const BYTE *data, DWORD len, std::string &out_b64)
{
    DWORD needed = 0;
    if (!CryptBinaryToStringA(data, len, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, NULL, &needed))
        return false;
    std::string tmp(needed, '\0');
    if (!CryptBinaryToStringA(data, len, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, &tmp[0], &needed))
        return false;
    // remove any trailing nulls
    if (!tmp.empty() && tmp.back() == '\0')
        tmp.pop_back();
    out_b64 = tmp;
    return true;
}

bool dpapi_load_blob_to_b64(const char *env_var, const char *path_env, std::string &out_b64)
{
    // Try env_var first
    const char *env_val = env_var ? std::getenv(env_var) : nullptr;
    std::vector<BYTE> blob_bytes;
    std::string raw;
    if (env_val && *env_val)
    {
        if (!base64_to_bin(env_val, blob_bytes))
            return false;
    }
    else
    {
        const char *path = path_env ? std::getenv(path_env) : nullptr;
        if (!path)
            return false;
        if (!read_file(path, raw))
            return false;
        // raw file content may be base64 or binary; try base64 decode first
        if (!base64_to_bin(raw, blob_bytes))
        {
            // use raw bytes directly
            blob_bytes.assign((BYTE *)raw.data(), (BYTE *)raw.data() + raw.size());
        }
    }

    DATA_BLOB in;
    in.pbData = blob_bytes.data();
    in.cbData = (DWORD)blob_bytes.size();

    DATA_BLOB out;
    if (!CryptUnprotectData(&in, NULL, NULL, NULL, NULL, 0, &out))
    {
      // If it fails, try with prompt disabled (standard for services)
      if (!CryptUnprotectData(&in, NULL, NULL, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &out))
      {
        return false;
      }
    }
    bool ok = bin_to_base64(out.pbData, out.cbData, out_b64);

    if (out.pbData)
        LocalFree(out.pbData);
    return ok;
}

#endif
