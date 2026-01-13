#pragma once

#include <string>

namespace crypto {

/**
 * Result of kernel response verification
 */
struct KernelVerificationResult {
    bool valid{false};
    std::string error_code;    // e.g., "SIGNATURE_INVALID", "SIGNATURE_MISSING"
    std::string error_message;
};

/**
 * Verify a kernel service response signature.
 * 
 * The kernel response includes:
 *   - request_id, status, kernel_exec_id, timestamp, error_code, error_message, result, signature
 * 
 * The signature is verified over canonical JSON (all fields except 'signature' in lexicographic order).
 * 
 * @param response_json The full response JSON string from kernel service
 * @param kernel_pubkey_b64 Optional base64 public key. If empty, uses env vars:
 *                          - KERNEL_PUBKEY_B64
 *                          - KERNEL_PUBKEY_DPAPI_B64 / KERNEL_PUBKEY_DPAPI_PATH
 *                          - KERNEL_PUBKEY_PATH
 * @return KernelVerificationResult indicating validity and any error details
 */
KernelVerificationResult verify_kernel_response(const std::string &response_json,
                                                 const std::string &kernel_pubkey_b64 = "");

/**
 * Build canonical JSON from a kernel response for signature verification.
 * Fields are sorted lexicographically, signature field is excluded.
 * 
 * @param response_json The full kernel response JSON
 * @return Canonical JSON string suitable for signature verification
 */
std::string build_canonical_kernel_response(const std::string &response_json);

/**
 * Verify a kernel response signature using kernel's public key.
 * Uses environment variables for key loading:
 *   - KERNEL_PUBKEY_B64 (direct base64)
 *   - KERNEL_PUBKEY_DPAPI_B64 / KERNEL_PUBKEY_DPAPI_PATH (DPAPI protected)
 *   - KERNEL_PUBKEY_PATH (file path)
 * 
 * @param message The canonical message that was signed
 * @param sig_b64 Base64-encoded signature
 * @param kernel_pubkey_b64 Optional explicit public key
 * @return true if signature is valid
 */
bool verify_kernel_signature(const std::string &message, const std::string &sig_b64,
                             const std::string &kernel_pubkey_b64 = "");

} // namespace crypto
