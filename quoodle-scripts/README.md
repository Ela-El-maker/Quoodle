# Ed25519 keys and usage

This folder is the central place for local secret tooling.

- `generate_ed25519_keys.py`: generate local Ed25519 keypair values.
- `print_ci_secret_commands.py`: print `gh secret set` commands for CI.
- `check_centralized_secrets.py`: validate required keys are set in root `.env`.

Generate keys (requires Python + PyNaCl):

```bash
python3 quoodle-scripts/generate_ed25519_keys.py > /dev/null
# The script prints two base64 strings: first is a 64-byte secret (secret+public),
# second is the public key. Copy them to environment variables as explained below.
```

Validate centralized secrets:

```bash
python3 quoodle-scripts/check_centralized_secrets.py --env-file .env
```

## Environment variables for local testing

- `ED25519_PRIVATE_KEY_B64` — base64-encoded 64-byte signing key for the agent (used by `quoodle-agent-windows`).
- `KERNEL_ED25519_SK_B64` — base64-encoded 64-byte signing key for the kernel service (if it must sign responses).
- `KERNEL_CONTROLLER_PUBKEY_B64` — base64-encoded public key for verifying controller-signed requests in `kernel-service`.

Set them for a shell session:

```bash
export ED25519_PRIVATE_KEY_B64="<base64-sk-64>"
export KERNEL_ED25519_SK_B64="<base64-sk-64>"
export KERNEL_CONTROLLER_PUBKEY_B64="<base64-pk-32>"
```

## CI and building

The CMake files will attempt to locate system `libsodium`. If missing, the build will fetch and build `libsodium` via `FetchContent` automatically so CI can run without a preinstalled package.
