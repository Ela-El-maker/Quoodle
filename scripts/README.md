Ed25519 keys and usage
======================

This folder contains a helper to generate Ed25519 keypairs for local development.

Generate keys (requires Python + PyNaCl):

```bash
python3 scripts/generate_ed25519_keys.py > /dev/null
# The script prints two base64 strings: first is a 64-byte secret (secret+public),
# second is the public key. Copy them to environment variables as explained below.
```

Environment variables for local testing
--------------------------------------
- `ED25519_PRIVATE_KEY_B64` — base64-encoded 64-byte signing key for the agent (used by `windows-agent`).
- `KERNEL_ED25519_SK_B64` — base64-encoded 64-byte signing key for the kernel service (if it must sign responses).
- `KERNEL_CONTROLLER_PUBKEY_B64` — base64-encoded public key for verifying controller-signed requests in `kernel-service`.

Set them for a shell session:

```bash
export ED25519_PRIVATE_KEY_B64="<base64-sk-64>"
export KERNEL_ED25519_SK_B64="<base64-sk-64>"
export KERNEL_CONTROLLER_PUBKEY_B64="<base64-pk-32>"
```

CI and building
----------------
The CMake files will attempt to locate system `libsodium`. If missing, the build will fetch and build `libsodium` via `FetchContent` automatically so CI can run without a preinstalled package.
