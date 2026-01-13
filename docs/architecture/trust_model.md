# Trust Model

- Mobile trusts Laravel via TLS + JWT
- FastAPI trusts Laravel via signed REST headers and JWKS
- Agent trusts FastAPI via WSS + signed envelopes and policy hash
- KernelService trusts Agent via Ed25519 on IOCTL requests and opcode allowlist
- Audit logs are hash-linked to detect tamper
