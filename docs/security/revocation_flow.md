# Revocation Flow

- JWT keys rotated and published via JWKS
- Device certificates revocable (simulated) via CRL list in CA service
- FastAPI rejects AUTH when JWT invalid/expired/revoked
- Agent enforces policy hash and rejects stale commands/updates
