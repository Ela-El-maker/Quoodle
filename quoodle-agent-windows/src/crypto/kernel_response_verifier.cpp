#include "kernel_response_verifier.hpp"
#include "json_canonicalizer.hpp"
#include "../logging/logger.hpp"

#ifdef HAVE_SODIUM
#include <sodium.h>
#include <vector>
#include <cstring>
#include <fstream>
#include <iterator>
#endif

#ifdef _WIN32
#include "../utils/dpapi_loader.hpp"
#endif

#include <nlohmann/json.hpp>
#include <sstream>
#include <iomanip>
#include <algorithm>

namespace crypto
{

  // Forward declaration for internal helper
  static std::string build_canonical_value(const nlohmann::json &value);

  /**
   * Recursively build canonical JSON value representation.
   */
  static std::string build_canonical_value(const nlohmann::json &value)
  {
    if (value.is_null())
    {
      return "null";
    }
    else if (value.is_boolean())
    {
      return value.get<bool>() ? "true" : "false";
    }
    else if (value.is_number_integer())
    {
      return std::to_string(value.get<std::int64_t>());
    }
    else if (value.is_number_unsigned())
    {
      return std::to_string(value.get<std::uint64_t>());
    }
    else if (value.is_number_float())
    {
      std::ostringstream oss;
      oss << std::setprecision(17) << value.get<double>();
      return oss.str();
    }
    else if (value.is_string())
    {
      return "\"" + escape_json(value.get<std::string>()) + "\"";
    }
    else if (value.is_array())
    {
      std::ostringstream oss;
      oss << "[";
      bool first = true;
      for (const auto &elem : value)
      {
        if (!first)
          oss << ",";
        first = false;
        oss << build_canonical_value(elem);
      }
      oss << "]";
      return oss.str();
    }
    else if (value.is_object())
    {
      // Get all keys and sort lexicographically
      std::vector<std::string> keys;
      for (auto it = value.begin(); it != value.end(); ++it)
      {
        keys.push_back(it.key());
      }
      std::sort(keys.begin(), keys.end());

      std::ostringstream oss;
      oss << "{";
      bool first = true;
      for (const auto &key : keys)
      {
        if (!first)
          oss << ",";
        first = false;
        oss << "\"" << key << "\":" << build_canonical_value(value[key]);
      }
      oss << "}";
      return oss.str();
    }
    return "";
  }

  std::string build_canonical_kernel_response(const std::string &response_json)
  {
    try
    {
      auto response = nlohmann::json::parse(response_json);

      // Remove the 'signature' field for canonical representation
      // Note: Kernel uses 'signature' or 'sig' depending on implementation
      if (response.contains("signature"))
      {
        response.erase("signature");
      }
      if (response.contains("sig"))
      {
        response.erase("sig");
      }

      return build_canonical_value(response);
    }
    catch (const std::exception &e)
    {
      Logger::log(LogLevel::Error, std::string("build_canonical_kernel_response: parse error: ") + e.what());
      return "";
    }
  }

  bool verify_kernel_signature(const std::string &message, const std::string &sig_b64,
                               const std::string &kernel_pubkey_b64)
  {
#ifdef HAVE_SODIUM
    if (sodium_init() < 0)
    {
      Logger::log(LogLevel::Error, "verify_kernel_signature: sodium_init failed");
      return false;
    }

    // If caller did not provide pubkey_b64, try environment or file path
    std::string pubkey_copy = kernel_pubkey_b64;
    if (pubkey_copy.empty())
    {
      const char *env_pk = std::getenv("KERNEL_PUBKEY_B64");
      if (env_pk && *env_pk)
      {
        pubkey_copy = env_pk;
      }
      else
      {
#ifdef _WIN32
        // Try DPAPI blob first
        std::string dpapi_b64;
        if (dpapi_load_blob_to_b64("KERNEL_PUBKEY_DPAPI_B64", "KERNEL_PUBKEY_DPAPI_PATH", dpapi_b64))
        {
          pubkey_copy = dpapi_b64;
        }
        else
#endif
        {
          const char *pk_path = std::getenv("KERNEL_PUBKEY_PATH");
          if (pk_path)
          {
            std::ifstream ifs(pk_path);
            if (ifs)
            {
              pubkey_copy.assign((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
              // Trim trailing newlines
              while (!pubkey_copy.empty() && (pubkey_copy.back() == '\n' || pubkey_copy.back() == '\r'))
                pubkey_copy.pop_back();
            }
          }
        }
      }
    }

    if (pubkey_copy.empty())
    {
      Logger::log(LogLevel::Error, "verify_kernel_signature: no kernel public key available");
      return false;
    }

    // Decode signature
    std::vector<unsigned char> sig(crypto_sign_BYTES);
    size_t sig_len = 0;
    if (sodium_base642bin(sig.data(), sig.size(), sig_b64.c_str(), sig_b64.size(), NULL, &sig_len, NULL, sodium_base64_VARIANT_ORIGINAL) != 0)
    {
      Logger::log(LogLevel::Error, "verify_kernel_signature: failed to decode signature base64");
      return false;
    }
    if (sig_len != crypto_sign_BYTES)
    {
      Logger::log(LogLevel::Error, "verify_kernel_signature: signature has unexpected length");
      return false;
    }

    // Decode public key
    std::vector<unsigned char> pk(crypto_sign_PUBLICKEYBYTES);
    size_t pk_len = 0;
    if (sodium_base642bin(pk.data(), pk.size(), pubkey_copy.c_str(), pubkey_copy.size(), NULL, &pk_len, NULL, sodium_base64_VARIANT_ORIGINAL) != 0)
    {
      Logger::log(LogLevel::Error, "verify_kernel_signature: failed to decode pubkey base64");
      return false;
    }
    if (pk_len != crypto_sign_PUBLICKEYBYTES)
    {
      Logger::log(LogLevel::Error, "verify_kernel_signature: pubkey has unexpected length");
      return false;
    }

    // Verify signature
    int ok = crypto_sign_verify_detached(sig.data(), reinterpret_cast<const unsigned char *>(message.data()), message.size(), pk.data());
    return ok == 0;
#else
    (void)message;
    (void)sig_b64;
    (void)kernel_pubkey_b64;
    Logger::log(LogLevel::Warn, "verify_kernel_signature: libsodium not available; refusing verification");
    return false;
#endif
  }

  KernelVerificationResult verify_kernel_response(const std::string &response_json,
                                                  const std::string &kernel_pubkey_b64)
  {
    KernelVerificationResult result;

    try
    {
      auto response = nlohmann::json::parse(response_json);

      // Extract signature (kernel may use 'signature' or 'sig')
      std::string sig = response.value("signature", "");
      if (sig.empty())
      {
        sig = response.value("sig", "");
      }

      if (sig.empty())
      {
        result.error_code = "SIGNATURE_MISSING";
        result.error_message = "Kernel response has no signature";
        return result;
      }

      // Build canonical payload for signature verification
      std::string canonical = build_canonical_kernel_response(response_json);
      if (canonical.empty())
      {
        result.error_code = "CANONICAL_BUILD_FAILED";
        result.error_message = "Failed to build canonical kernel response";
        return result;
      }

      // Verify signature
      bool sig_valid = verify_kernel_signature(canonical, sig, kernel_pubkey_b64);
      if (!sig_valid)
      {
        result.error_code = "SIGNATURE_INVALID";
        result.error_message = "Ed25519 kernel response signature verification failed";
        return result;
      }

      // All checks passed
      result.valid = true;
      return result;
    }
    catch (const std::exception &e)
    {
      result.error_code = "PARSE_ERROR";
      result.error_message = std::string("Failed to parse kernel response: ") + e.what();
      return result;
    }
  }

} // namespace crypto
