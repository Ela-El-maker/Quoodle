# FastAPI Controller
Implements WSS control channel for agents, REST webhooks to Laravel, and telemetry/command routing per docs/specs.

## Security-critical configuration

To fully meet the protocol and security requirements in `docs/specs` and `docs/security`:

Device public key registry:


Replay protection:


### Laravel ↔ FastAPI control-plane signing

FastAPI must not trust unsigned internal POSTs. Enable verification of Laravel-signed requests:

- `REQUIRE_LARAVEL_SIGNATURE` (default: `false`): When `true`, FastAPI enforces `X-Laravel-Signature` on `POST /api/v1/command/dispatch`.
- `LARAVEL_SERVICE_PUBKEY_B64`: Base64-encoded Ed25519 public key for the Laravel service.

### FastAPI → Laravel webhook signing

Laravel must not trust inbound webhooks without verifying the sender.

- `SIGN_LARAVEL_WEBHOOKS` (default: `false`): When `true`, FastAPI signs outbound webhook requests to Laravel.
- `FASTAPI_SERVICE_PRIVATE_KEY_B64`: Base64-encoded Ed25519 private key for the FastAPI service.

Message signing:

- `REQUIRE_ED25519` (default `true`): Require Ed25519 signing/verification (PyNaCl).
- `ALLOW_DEV_SIG_FALLBACK` (default `false`): If `true`, allows deterministic SHA256 fallback when Ed25519 signing is unavailable (dev-only).

Controller signing key (outbound controller messages):

- `ED25519_PRIVATE_KEY_B64` or `ED25519_PRIVATE_KEY_PATH` or `ED25519_PRIVATE_KEY_DPAPI_B64` / `ED25519_PRIVATE_KEY_DPAPI_PATH`
