# CI Ed25519 Test Keys

This document explains how to generate test Ed25519 keys and add them as GitHub Actions secrets so the signed-request integration test runs in CI.

Secrets the CI workflow expects (Windows job):

- `CI_ED25519_SK_B64` — base64-encoded 64-byte signing secret (secret+public). Used by the service/agent in CI tests.
- `CI_ED25519_PUB_B64` — base64-encoded 32-byte public key (controller pubkey) used by the kernel-service to verify incoming signed requests.

Steps (recommended):

1. Generate keys locally (requires Python + PyNaCl):

```bash
python3 scripts/generate_ed25519_keys.py
```

The script prints two base64 strings: first the 64-byte secret (secret+public), second the public key.

2. Add secrets to GitHub (using `gh` CLI), run in a safe shell on your machine (replace <base64> with values from step 1):

```bash
# Set secret key
gh secret set CI_ED25519_SK_B64 --body "<base64-secret-64>"
# Set public key
gh secret set CI_ED25519_PUB_B64 --body "<base64-pub-32>"
```

If you prefer the web UI: repo Settings → Secrets and variables → Actions → New repository secret; add the two values above.

3. Trigger CI (push/PR) — the Windows runner will run the signed-request integration test.

Security note:
- Do NOT commit private keys into the repository. Use GitHub Secrets or a secure secret manager in production.

