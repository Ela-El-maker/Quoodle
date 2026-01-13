# Windows Agent Module Layout

These folders isolate agent functionality so recovery, attestation, OTA, and quarantine logic can be developed and tested independently from the main agent loop.

- `recovery/`: Health checks, dependency verification, and self-repair flows for FastAPI downtime, cert expiry, or local DB corruption.
- `attestation/`: CSR generation, cert storage (DPAPI-protected), revocation checks, and attestation responses to FastAPI.
- `logging/`: Local structured logs, rotation policy, and tamper-evident hash chaining before upload.
- `ota/`: OTA update download, signature verification, staged rollout handling, and rollback snapshots.
- `quarantine/`: Local enforcement of quarantine commands, command deny lists, and UX prompts for restricted mode.
