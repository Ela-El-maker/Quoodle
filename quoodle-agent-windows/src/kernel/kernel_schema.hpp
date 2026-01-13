#pragma once

#include <cstdint>
#include <string>

/**
 * KernelRequest
 * Represents a signed request from the Agent to the Kernel Service.
 * All fields except signature are included in the canonical payload for signing.
 */
struct KernelRequest
{
  std::string request_id;          // Unique request identifier
  std::string timestamp;           // ISO 8601 UTC timestamp (e.g., "2026-01-13T12:00:00Z")
  std::string opcode;              // Operation code (e.g., "EXEC_LOCK_SCREEN", "ping")
  std::string params;              // JSON object of operation parameters
  std::uint64_t agent_sequence{0}; // Monotonically increasing sequence number
  std::string policy_hash;         // Hash of current policy bundle (sha256:xxx...)
  std::string command_message_id;  // Originating command ID from controller
  std::string signature;           // Base64 Ed25519 signature over canonical payload
};

struct KernelResponseSchema
{
  std::string request_id;
  std::string status;
  std::string kernel_exec_id;
  std::string timestamp;
  int error_code{0};
  std::string error_message;
  std::string result;
  std::string signature;
};
