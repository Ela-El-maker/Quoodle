# Integrity checks (planned)

This directory is for integrity and tamper-detection helpers used by `kernel-service`.
It may contain canonical file lists, reference hashes, and tools to compute/verify
measurements. In dev mode the service uses a lightweight fingerprinting implementation
in `service/opcodes/tamper_check.cpp`.

Planned artifacts:
- Reference manifests
- Hash tooling
- Verification agents
