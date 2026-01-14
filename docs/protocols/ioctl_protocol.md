# IOCTL Protocol Summary

Request schema:
equest_id, timestamp, opcode, params, agent_sequence, policy_hash, command_message_id, signature.
Response schema:
equest_id, status, kernel_exec_id, timestamp, error_code, error_message, result, signature.quoodle-agent-windows
Allowed opcodes match JSON spec (lock, reboot, shutdown, logout, process list, attestation, tamper, stage/commit/rollback update, validate package, ping).
Dispatcher implementation in kernel-service/service enforces opcode allowlist and schema validation; Agent bridge in windows-agent/src/kernel/ioctl_client.cpp builds canonical requests.
