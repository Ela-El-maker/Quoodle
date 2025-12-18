#!/usr/bin/env python3
"""
Generate Ed25519 keypair and print GitHub CLI commands to set CI secrets.
Requires: Python3, PyNaCl, and `gh` CLI (optional - commands printed for manual use).
"""
import subprocess
import sys
import shlex

try:
    out = subprocess.check_output([sys.executable, "scripts/generate_ed25519_keys.py"], text=True)
except subprocess.CalledProcessError as e:
    print("Failed to run key generator:", e, file=sys.stderr)
    sys.exit(2)

# Extract base64 lines (skip comment lines)
lines = [l.strip() for l in out.splitlines() if l.strip() and not l.strip().startswith('#')]
if len(lines) < 2:
    print("Unexpected generator output:\n", out)
    sys.exit(2)

sk_b64 = lines[0]
pk_b64 = lines[1]

print("# Copy-paste the following commands to set secrets via gh CLI (change repo if needed):\n")
print(f"gh secret set CI_ED25519_SK_B64 --body \"{sk_b64}\"")
print(f"gh secret set CI_ED25519_PUB_B64 --body \"{pk_b64}\"")

print("\n# Or set them via GitHub web UI under Settings → Secrets and variables → Actions")
