#include "ed25519_wrapper.hpp"
#include "utils/logger.hpp"

// Move all headers and helper functions inside the guard
// so they only compile when libsodium is actually present.
#ifdef HAVE_SODIUM
#include <sodium.h>
#include <vector>
#include <cstdlib>
#include <cstring>
#include <fstream>   // Defines std::ifstream
#include <streambuf> // Defines std::istreambuf_iterator
#include <string>
#include "../utils/dpapi_loader.hpp"

static bool read_file_to_string(const char *path, std::string &out)
{
  if (!path)
    return false;

  std::ifstream ifs(path, std::ios::in | std::ios::binary);
  if (!ifs.is_open()) // Better than !ifs for some compilers
    return false;

  out.assign((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
  return true;
}
#endif

std::string ed25519_sign_message(const std::string &message)
{
#ifdef HAVE_SODIUM
  if (sodium_init() < 0)
  {
    utils::log_error("ed25519_wrapper: sodium_init failed");
    return {};
  }

  const char *b64 = std::getenv("KERNEL_ED25519_SK_B64");
  std::string skfile;
  // Try DPAPI-protected blob first when env var/path not provided
  if (!b64)
  {
    std::string dpapi_b64;
    if (dpapi_load_blob_to_b64("KERNEL_ED25519_SK_DPAPI_B64", "KERNEL_ED25519_SK_DPAPI_PATH", dpapi_b64))
    {
      skfile = dpapi_b64;
      b64 = skfile.c_str();
    }
    else
    {
      const char *sk_path = std::getenv("KERNEL_ED25519_SK_PATH");
      if (!read_file_to_string(sk_path, skfile))
      {
        utils::log_warn("ed25519_wrapper: KERNEL_ED25519_SK_B64 not set and SK_PATH/DPAPI not readable; cannot sign");
        return {};
      }
      // trim newline
      while (!skfile.empty() && (skfile.back() == '\n' || skfile.back() == '\r'))
        skfile.pop_back();
      b64 = skfile.c_str();
    }
  }

  std::vector<unsigned char> sk(64);
  size_t bin_len = 0;
  if (sodium_base642bin(sk.data(), sk.size(), b64, strlen(b64), NULL, &bin_len, NULL, sodium_base64_VARIANT_ORIGINAL) != 0)
  {
    utils::log_error("ed25519_wrapper: failed to decode base64 SK");
    return {};
  }

  if (bin_len != 64)
  {
    utils::log_error("ed25519_wrapper: decoded SK has unexpected length");
    return {};
  }

  unsigned char sig[crypto_sign_BYTES];
  if (crypto_sign_detached(sig, NULL, reinterpret_cast<const unsigned char *>(message.data()), message.size(), sk.data()) != 0)
  {
    utils::log_error("ed25519_wrapper: crypto_sign_detached failed");
    return {};
  }

  char out_b64[crypto_sign_BYTES * 2 + 16];
  sodium_bin2base64(out_b64, sizeof(out_b64), sig, crypto_sign_BYTES, sodium_base64_VARIANT_ORIGINAL);
  // After signing is finished
sodium_memzero(sk.data(), sk.size()); // Clears the secret from RAM immediately
return std::string(out_b64);
#else
  (void)message;
  utils::log_warn("ed25519_wrapper: libsodium not available at build time; signing disabled");
  return {};
#endif
}
