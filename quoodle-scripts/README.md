# quoodle-scripts

Helper utilities for local key generation, secret hygiene, and trust-chain validation.

## 1. Purpose

This folder supports cryptographic bootstrap and environment consistency checks for development and CI.

## 2. Tools

- `generate_ed25519_keys.py`
- `print_ci_secret_commands.py`
- `check_centralized_secrets.py`

## 3. Cryptographic Strategy Notes

Local trust chain depends on key consistency across:

- control-plane/gateway signing source
- agent verifier inputs
- privileged boundary verifier inputs

These scripts help avoid silent drift during local resets and pairing churn.

## 4. Generate Keys

Requires Python and PyNaCl.

```bash
python3 quoodle-scripts/generate_ed25519_keys.py
```

## 5. Validate Secret Set

```bash
python3 quoodle-scripts/check_centralized_secrets.py --env-file .env
```

## 6. CI Secret Command Template

```bash
python3 quoodle-scripts/print_ci_secret_commands.py
```

## 7. Relevant Variables

- `ED25519_PRIVATE_KEY_B64`
- `KERNEL_ED25519_SK_B64`
- `KERNEL_CONTROLLER_PUBKEY_B64`

Shell example:

```bash
export ED25519_PRIVATE_KEY_B64="<base64-64-byte-secret>"
export KERNEL_ED25519_SK_B64="<base64-64-byte-secret>"
export KERNEL_CONTROLLER_PUBKEY_B64="<base64-public-key>"
```

## 8. Operational Guidance

- never commit private key material
- rotate keys when rebuilding trust chains
- refresh runtime artifacts and restart services after key changes
- verify published controller public key matches local verifier inputs before command testing

## 9. Sequence Diagrams

### 9.1 Local Key Rotation Consistency

```text
Dev/Ops            generate_ed25519_keys      .env / secrets      Services
  |                        |                       |                 |
  | run script             | create keypair        |                 |
  |----------------------->|---------------------->| update values   |
  | restart runtimes       |                       |---------------->|
  | verify signatures      |                       |                 |
```

### 9.2 Secret Validation Gate

```text
check_centralized_secrets.py      .env file        CI/Operator
             |                        |                 |
             | parse required vars    |                 |
             |----------------------->|                 |
             | missing? fail report   |---------------> |
             | complete? pass         |---------------> |
```
