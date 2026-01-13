#!/usr/bin/env python3
"""
Generate Ed25519 keypair and print base64-encoded secret (64 bytes) and public key.

Requirements:
- Python 3
- PyNaCl (preferred): `pip install pynacl`

If PyNaCl is unavailable, the script will exit with instructions.
"""
import base64
import sys

try:
    from nacl import signing
except Exception:
    print("PyNaCl is required. Install with: pip install pynacl", file=sys.stderr)
    sys.exit(2)

def main():
    key = signing.SigningKey.generate()
    sk = key.encode() + key.verify_key.encode()  # 64 bytes: secret + public
    pk = key.verify_key.encode()
    print("# Base64-encoded 64-byte secret key (store in ED25519_PRIVATE_KEY_B64 or KERNEL_ED25519_SK_B64)")
    print(base64.b64encode(sk).decode())
    print()
    print("# Base64-encoded public key (store in KERNEL_CONTROLLER_PUBKEY_B64 or controller side)")
    print(base64.b64encode(pk).decode())

if __name__ == '__main__':
    main()
