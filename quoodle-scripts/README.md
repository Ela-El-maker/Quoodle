# quoodle-scripts

Helper utilities for local key material and environment validation.

## 1. Purpose

This folder centralizes helper scripts that support local signing/bootstrap workflows.

## 2. Tools

- `generate_ed25519_keys.py`
  - generates local Ed25519 key material for dev use
- `print_ci_secret_commands.py`
  - emits `gh secret set` command templates
- `check_centralized_secrets.py`
  - validates required root `.env` secret presence

## 3. Generate Keys

Requires Python and PyNaCl.

```bash
python3 quoodle-scripts/generate_ed25519_keys.py
```

## 4. Validate Local Secret Set

```bash
python3 quoodle-scripts/check_centralized_secrets.py --env-file .env
```

## 5. Relevant Environment Variables

- `ED25519_PRIVATE_KEY_B64`
- `KERNEL_ED25519_SK_B64`
- `KERNEL_CONTROLLER_PUBKEY_B64`

Set for current shell (Linux/macOS shell style):

```bash
export ED25519_PRIVATE_KEY_B64="<base64-64-byte-secret>"
export KERNEL_ED25519_SK_B64="<base64-64-byte-secret>"
export KERNEL_CONTROLLER_PUBKEY_B64="<base64-public-key>"
```

## 6. Notes

- keep these values out of committed files
- rotate keys when resetting local trust chains
- align controller public key with active gateway signer before command validation
