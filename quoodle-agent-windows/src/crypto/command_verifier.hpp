#pragma once

#include <string>
#include <cstdint>

namespace crypto
{

    /**
     * Result of command envelope verification
     */
    struct VerificationResult
    {
        bool valid{false};
        std::string error_code; // e.g., "SIGNATURE_INVALID", "TTL_EXPIRED", "SEQ_REPLAY"
        std::string error_message;
    };

    /**
     * Verify a COMMAND_DELIVERY envelope from the controller.
     *
     * Checks:
     * 1. Signature over canonical envelope (excluding 'sig' field)
     * 2. TTL has not expired
     * 3. Sequence number > last received sequence (replay protection)
     *
     * @param envelope_json The full command_envelope JSON object as string
     * @param last_seq The last sequence number received from this controller
     * @param controller_pubkey_b64 Optional base64 public key. If empty, uses env vars.
     * @return VerificationResult indicating validity and any error details
     */
    VerificationResult verify_command_envelope(const std::string &envelope_json,
                                               std::uint64_t last_seq,
                                               const std::string &controller_pubkey_b64 = "");

    /**
     * Build canonical JSON from a command envelope for signature verification.
     * Fields are sorted lexicographically, signature field is excluded.
     *
     * @param envelope_json The full command_envelope JSON object
     * @return Canonical JSON string suitable for signature verification
     */
    std::string build_canonical_envelope(const std::string &envelope_json);

    /**
     * Check if the TTL of an envelope has expired.
     *
     * @param timestamp_iso8601 The timestamp from the envelope header
     * @param ttl_seconds The TTL in seconds
     * @return true if still valid, false if expired
     */
    bool check_ttl(const std::string &timestamp_iso8601, int ttl_seconds);

    /**
     * Parse ISO8601 timestamp to epoch seconds.
     * Supports format: "2026-01-13T12:00:00Z"
     */
    std::int64_t parse_iso8601_to_epoch(const std::string &timestamp);

} // namespace crypto
