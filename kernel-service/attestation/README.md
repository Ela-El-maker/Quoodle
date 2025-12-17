# Attestation module (planned)

This folder holds attestation-related code (TPM interactions, quote verification,
nonce generation, and attestation bundling). For dev/test we include a lightweight
attestation stub in `service/opcodes/attestation.cpp` that returns a structured
attestation object. Production integration should call the platform TPM APIs.

Planned artifacts:
- TPM quote reader
- Attestation bundle formatter
- Remote verification helpers
