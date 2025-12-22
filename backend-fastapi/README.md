# FastAPI Controller
Implements WSS control channel for agents, REST webhooks to Laravel, and telemetry/command routing per docs/specs.

## Security-critical configuration

To fully meet the protocol and security requirements in `docs/specs` and `docs/security`:

Device public key registry:

- `DEVICE_REGISTRY_DB_PATH` (default `./data/device_registry.db`): SQLite DB storing `device_id -> ed25519_pub_b64`.
- `DEVICE_PUBKEYS_PATH` (optional): JSON file used to seed the registry, e.g. `{ "PC001": "<PUBKEY_B64>", ... }`.

Replay protection:

- `REDIS_URL` (recommended in production): Enables Redis-backed replay protection.
- `MAX_CLOCK_SKEW_SECONDS` (default `5`): Reject inbound messages if timestamp skew exceeds this.
- `REQUIRE_AGENT_SEQ` (default `true`): Require and enforce monotonic `seq` on inbound messages.

Message signing:

- `REQUIRE_ED25519` (default `true`): Require Ed25519 signing/verification (PyNaCl).
- `ALLOW_DEV_SIG_FALLBACK` (default `false`): If `true`, allows deterministic SHA256 fallback when Ed25519 signing is unavailable (dev-only).

Controller signing key (outbound controller messages):

- `ED25519_PRIVATE_KEY_B64` or `ED25519_PRIVATE_KEY_PATH` or `ED25519_PRIVATE_KEY_DPAPI_B64` / `ED25519_PRIVATE_KEY_DPAPI_PATH`
