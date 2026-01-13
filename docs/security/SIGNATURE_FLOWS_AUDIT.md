# Security Audit: Signature Flows

**Audit Date:** 2026-01-13  
**Scope:** Ed25519 and JWT signature flows across all Quoodle components  
**Status:** ✅ PASSED with recommendations

---

## Executive Summary

The Quoodle Secure Device Control System implements a comprehensive cryptographic trust chain using Ed25519 signatures for command/response integrity and PS256/RS256 for JWT authentication. This audit found the implementation to be **sound** with consistent canonical JSON handling across all components and proper signature verification at each trust boundary.

### Key Findings

| Category             | Status        | Notes                                |
| -------------------- | ------------- | ------------------------------------ |
| Ed25519 Signing      | ✅ SECURE     | Consistent across all components     |
| Ed25519 Verification | ✅ SECURE     | Proper key validation                |
| JWT Authentication   | ✅ SECURE     | RS256/PS256 with session revocation  |
| Canonical JSON       | ✅ CONSISTENT | Same algorithm in PHP, Python, C++   |
| Key Storage          | ⚠️ ACCEPTABLE | DPAPI on Windows, env vars elsewhere |
| Replay Protection    | ✅ SECURE     | Sequence numbers + nonce + TTL       |

---

## Component Analysis

### 1. Laravel Control Plane (`quoodle-control-plane`)

#### 1.1 Ed25519 Signing

**File:** [app/Services/Security/Ed25519Signer.php](../../quoodle-control-plane/app/Services/Security/Ed25519Signer.php)

```
Flow: Laravel → FastAPI (webhooks)
Algorithm: Ed25519 (detached signature)
Library: ext-sodium (native PHP)
Key source: LARAVEL_SERVICE_PRIVATE_KEY_B64 (env)
```

**Implementation Review:**

- ✅ Uses `sodium_crypto_sign_detached()` correctly
- ✅ Validates base64 decoding before signing
- ✅ Signs canonical JSON bytes (not raw payload)
- ✅ Returns base64-encoded signature

#### 1.2 Canonical JSON

**File:** [app/Services/Security/Ed25519CanonicalJson.php](../../quoodle-control-plane/app/Services/Security/Ed25519CanonicalJson.php)

```
Algorithm:
1. Recursively sort object keys lexicographically
2. Preserve array element order
3. JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION
4. No whitespace
```

**Implementation Review:**

- ✅ Recursive key sorting implemented correctly
- ✅ Lists (indexed arrays) preserve order
- ✅ `stripSig()` removes signature field before verification
- ✅ Handles nested objects/arrays

#### 1.3 JWT Authentication

**File:** [app/Services/JWT/JWTSigner.php](../../quoodle-control-plane/app/Services/JWT/JWTSigner.php)

```
Algorithm: RS256 (fallback from PS256)
Library: firebase/php-jwt
Claims: iss, aud, iat, nbf, exp, jti, sub, session_id, email
TTL: 900 seconds (configurable)
```

**Implementation Review:**

- ✅ PS256 → RS256 fallback for compatibility
- ✅ Key loaded from file (not hardcoded)
- ✅ Standard JWT claims with session tracking
- ✅ Key ID (kid) included in header

#### 1.4 FastAPI Signature Verification (Inbound)

**File:** [app/Http/Middleware/VerifyFastApiSignature.php](../../quoodle-control-plane/app/Http/Middleware/VerifyFastApiSignature.php)

```
Header: X-FastAPI-Signature
Verification: sodium_crypto_sign_verify_detached()
Key: FASTAPI_SERVICE_PUBLIC_KEY_B64
```

**Implementation Review:**

- ✅ Feature flag for enable/disable
- ✅ Proper base64 validation
- ✅ Canonical JSON before verification
- ✅ Returns 401 on invalid signature

---

### 2. FastAPI Gateway (`quoodle-gateway`)

#### 2.1 Ed25519 Verification

**File:** [app/ws/signing.py](../../quoodle-gateway/app/ws/signing.py)

```
Library: PyNaCl (nacl.signing.VerifyKey)
Functions:
  - verify_ed25519_detached(message, sig_b64, pubkey_b64)
  - verify_ed25519_signature(payload, pubkey_b64)  # extracts 'sig' field
```

**Implementation Review:**

- ✅ Uses PyNaCl's verified VerifyKey implementation
- ✅ Graceful handling when PyNaCl unavailable
- ✅ Proper base64 decoding with error handling
- ✅ Two verification modes (detached + inline sig)

#### 2.2 Ed25519 Signing (Outbound)

**File:** [app/services/fastapi_service_signing.py](../../quoodle-gateway/app/services/fastapi_service_signing.py)

```
Library: PyNaCl (nacl.signing.SigningKey)
Header: X-FastAPI-Signature
Key: FASTAPI_SERVICE_PRIVATE_KEY_B64
```

**Implementation Review:**

- ✅ Accepts both 32-byte seed and 64-byte key formats
- ✅ Signs canonical JSON bytes
- ✅ Feature flag for enable/disable
- ⚠️ Key not zeroed after use (Python limitation)

#### 2.3 Canonical JSON

**File:** [app/ws/canonical.py](../../quoodle-gateway/app/ws/canonical.py)

```
Algorithm:
1. Recursively normalize dict keys to strings
2. Sort keys lexicographically
3. json.dumps with sort_keys=True, separators=(",", ":")
4. UTF-8 encoding
```

**Implementation Review:**

- ✅ Matches PHP implementation
- ✅ `strip_sig()` removes 'sig' key recursively
- ✅ Disallows NaN/Infinity
- ✅ Returns bytes (not string)

#### 2.4 Replay Protection

**File:** [app/services/replay_protection.py](../../quoodle-gateway/app/services/replay_protection.py)

```
Mechanisms:
1. Timestamp validation (max clock skew: 5 seconds)
2. Sequence number tracking (Redis or in-memory)
3. Nonce deduplication (Redis SETNX with TTL)
```

**Implementation Review:**

- ✅ Redis-backed with atomic Lua script for seq
- ✅ In-memory fallback for dev/test
- ✅ ISO8601 timestamp parsing with timezone handling
- ✅ Configurable clock skew tolerance

#### 2.5 Laravel Bridge Auth

**File:** [app/services/laravel_bridge_auth.py](../../quoodle-gateway/app/services/laravel_bridge_auth.py)

```
Header: X-Laravel-Signature
Key: LARAVEL_SERVICE_PUBKEY_B64
```

**Implementation Review:**

- ✅ Feature flag for enable/disable
- ✅ 500 error if key not configured (fail-closed)
- ✅ Canonical JSON verification

---

### 3. Windows Agent (`quoodle-agent-windows`)

#### 3.1 Ed25519 Signing (Agent → Kernel)

**File:** [src/crypto/ed25519_sign.cpp](../../quoodle-agent-windows/src/crypto/ed25519_sign.cpp)

```
Library: libsodium
Key sources (priority order):
  1. ED25519_PRIVATE_KEY_B64 (env)
  2. ED25519_PRIVATE_KEY_DPAPI_B64 (DPAPI blob)
  3. ED25519_PRIVATE_KEY_DPAPI_PATH (DPAPI file)
```

**Implementation Review:**

- ✅ `sodium_crypto_sign_detached()` correct usage
- ✅ DPAPI support for Windows key protection
- ✅ Validates key length (64 bytes)
- ⚠️ Returns empty string on error (not exception)
- ⚠️ Key not zeroed after use (memory leak risk)

**Recommendation:** Add `sodium_memzero()` after signing operation.

#### 3.2 Ed25519 Verification (Controller → Agent)

**File:** [src/crypto/ed25519_verify.cpp](../../quoodle-agent-windows/src/crypto/ed25519_verify.cpp)

```
Library: libsodium
Key sources (priority order):
  1. pubkey_b64 parameter
  2. CONTROLLER_PUBKEY_B64 (env)
  3. CONTROLLER_PUBKEY_DPAPI_B64/PATH (DPAPI)
  4. CONTROLLER_PUBKEY_PATH (file)
```

**Implementation Review:**

- ✅ `crypto_sign_verify_detached()` correct usage
- ✅ Multiple key source fallbacks
- ✅ DPAPI support for secure key storage
- ✅ Validates signature and key lengths

#### 3.3 Command Verification

**File:** [src/crypto/command_verifier.cpp](../../quoodle-agent-windows/src/crypto/command_verifier.cpp)

```
Checks:
1. Signature presence and validity
2. Sequence number (replay protection)
3. TTL expiration (timestamp + ttl_seconds)
4. Canonical envelope construction
```

**Implementation Review:**

- ✅ Comprehensive verification pipeline
- ✅ Detailed error codes (SIGNATURE_MISSING, SEQ_REPLAY, TTL_EXPIRED, etc.)
- ✅ Canonical JSON matches PHP/Python implementations
- ✅ Removes 'sig' field before canonicalization

#### 3.4 Canonical JSON

**File:** [src/crypto/json_canonicalizer.cpp](../../quoodle-agent-windows/src/crypto/json_canonicalizer.cpp)

```
Algorithm:
1. Sort object keys lexicographically (std::sort)
2. Recursive value processing
3. JSON escape sequences for special chars
4. No whitespace
```

**Implementation Review:**

- ✅ Matches PHP/Python implementations
- ✅ Proper JSON escaping (\\, \", \n, \r, \t, \uXXXX)
- ✅ Number formatting with precision

---

### 4. Kernel Service (`quoodle-kernel-guard`)

#### 4.1 Ed25519 Signing (Kernel → Agent)

**File:** [service/crypto/ed25519_wrapper.cpp](../../quoodle-kernel-guard/service/crypto/ed25519_wrapper.cpp)

```
Library: libsodium
Key sources:
  1. KERNEL_ED25519_SK_B64 (env)
  2. KERNEL_ED25519_SK_DPAPI_B64/PATH (DPAPI)
  3. KERNEL_ED25519_SK_PATH (file)
```

**Implementation Review:**

- ✅ `crypto_sign_detached()` correct usage
- ✅ **Key zeroing after use** (`sodium_memzero`) ← Best practice!
- ✅ DPAPI support for Windows
- ✅ Validates key length

#### 4.2 Ed25519 Verification (Agent → Kernel)

**File:** [service/crypto/ed25519_verify_wrapper.cpp](../../quoodle-kernel-guard/service/crypto/ed25519_verify_wrapper.cpp)

```
Library: libsodium
Key sources:
  1. pubkey_b64 parameter
  2. KERNEL_CONTROLLER_PUBKEY_B64 (env)
  3. KERNEL_CONTROLLER_PUBKEY_DPAPI_B64/PATH (DPAPI)
  4. KERNEL_CONTROLLER_PUBKEY_PATH (file)
```

**Implementation Review:**

- ✅ Matches Agent verification implementation
- ✅ DPAPI support
- ✅ Fail-closed when libsodium unavailable

#### 4.3 Request Signature Verification

**File:** [service/main.cpp](../../quoodle-kernel-guard/service/main.cpp) (lines 145-250)

```
Canonical fields (lexicographic order):
- agent_sequence
- command_message_id
- opcode
- params (JSON object)
- policy_hash
- request_id
- timestamp

Toggle: KERNEL_REQUIRE_SIGNATURE=1
```

**Implementation Review:**

- ✅ Explicit field ordering for determinism
- ✅ Feature flag for dev/test flexibility
- ✅ Detailed error responses (SIGNATURE_MISSING, SIGNATURE_INVALID)
- ✅ Request ID preserved in error responses

---

## Trust Chain Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TRUST CHAIN OVERVIEW                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    JWT (RS256)    ┌──────────────┐                        │
│  │   Mobile     │ ─────────────────▶│   Laravel    │                        │
│  │     App      │                   │ Control Plane │                        │
│  └──────────────┘                   └──────┬───────┘                        │
│                                            │                                 │
│                                   Ed25519  │ X-Laravel-Signature            │
│                                            ▼                                 │
│                                    ┌──────────────┐                         │
│                                    │   FastAPI    │                         │
│                                    │   Gateway    │                         │
│                                    └──────┬───────┘                         │
│                                           │                                  │
│                          Ed25519 (WebSocket│ envelope.sig)                   │
│                                           ▼                                  │
│                                    ┌──────────────┐                         │
│                                    │   Windows    │                         │
│                                    │    Agent     │                         │
│                                    └──────┬───────┘                         │
│                                           │                                  │
│                           Ed25519 (IOCTL  │ request.signature)              │
│                                           ▼                                  │
│                                    ┌──────────────┐                         │
│                                    │   Kernel     │                         │
│                                    │   Service    │                         │
│                                    └──────────────┘                         │
│                                                                              │
│  Response flow (reverse direction) also signed with Ed25519                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Management Summary

| Component | Private Key Source              | Public Key Source              | Protection       |
| --------- | ------------------------------- | ------------------------------ | ---------------- |
| Laravel   | JWT_PRIVATE_KEY_PATH            | JWT_PUBLIC_KEY_PATH            | File permissions |
| Laravel   | LARAVEL_SERVICE_PRIVATE_KEY_B64 | FASTAPI_SERVICE_PUBLIC_KEY_B64 | Env vars         |
| FastAPI   | FASTAPI_SERVICE_PRIVATE_KEY_B64 | LARAVEL_SERVICE_PUBKEY_B64     | Env vars         |
| Agent     | ED25519_PRIVATE_KEY_B64         | CONTROLLER_PUBKEY_B64          | DPAPI (Windows)  |
| Kernel    | KERNEL_ED25519_SK_B64           | KERNEL_CONTROLLER_PUBKEY_B64   | DPAPI (Windows)  |

---

## Vulnerabilities & Mitigations

### ⚠️ LOW: Key Not Zeroed in Agent Signing

**Location:** `quoodle-agent-windows/src/crypto/ed25519_sign.cpp`

**Issue:** Private key remains in memory after signing operation.

**Risk:** Memory dump could expose key.

**Mitigation:** Add `sodium_memzero(sk.data(), sk.size())` after signing (already done in Kernel).

**Severity:** LOW (requires memory access)

---

### ⚠️ LOW: Environment Variable Key Storage

**Location:** All components

**Issue:** Ed25519 keys stored in environment variables.

**Risk:** Process listing or env dumps could expose keys.

**Mitigation:**

- Windows: DPAPI blobs (already implemented)
- Linux/containers: Use secret managers (Vault, K8s secrets)
- Consider: HSM integration for production

**Severity:** LOW (standard practice, DPAPI helps on Windows)

---

### ✅ ACCEPTABLE: Hash Algorithm Fallback

**Location:** `quoodle-control-plane/app/Services/JWT/JWTSigner.php`

**Issue:** PS256 falls back to RS256 due to PHP compatibility.

**Risk:** RS256 is slightly less secure than PS256 (deterministic vs probabilistic padding).

**Mitigation:** RS256 is still considered secure. Upgrade PHP/OpenSSL for PS256 if required.

**Severity:** ACCEPTABLE (RS256 is industry standard)

---

### ✅ MITIGATED: Replay Attacks

**Protection Layers:**

1. Monotonically increasing sequence numbers per device
2. Timestamp validation with max 5s clock skew
3. Nonce deduplication via Redis SETNX
4. TTL enforcement on command envelopes

**Status:** SECURE

---

## Recommendations

### High Priority

1. **Add key zeroing in Agent:** Update `ed25519_sign.cpp` to zero key after use.

### Medium Priority

2. **Document key rotation procedure:** Create runbook for rotating Ed25519 key pairs.

3. **Add key expiration monitoring:** Alert when keys approach rotation schedule.

4. **Integration tests:** Add cross-component signature verification tests.

### Low Priority

5. **Consider HSM integration:** For highest-security deployments.

6. **Audit log signatures:** Consider signing audit logs for tamper evidence.

---

## Test Coverage

| Component          | Test File                                             | Coverage         |
| ------------------ | ----------------------------------------------------- | ---------------- |
| Laravel Ed25519    | `tests/Unit/Ed25519SignerTest.php`                    | ✅ Sign + verify |
| Laravel Middleware | `tests/Unit/VerifyFastApiSignatureMiddlewareTest.php` | ✅ Valid/invalid |
| FastAPI Ed25519    | `tests/test_security_pillars.py`                      | ✅ Sign + verify |
| FastAPI Replay     | `tests/test_security_pillars.py`                      | ✅ Seq + nonce   |
| Agent Verify       | Unit tests needed                                     | ⚠️ Partial       |
| Kernel Verify      | Unit tests needed                                     | ⚠️ Partial       |

---

## Conclusion

The Quoodle signature flow implementation is **secure and well-designed**. The canonical JSON algorithms are consistent across PHP, Python, and C++, ensuring cross-component signature compatibility. Replay protection is comprehensive with multiple defense layers.

**Recommended Action:** Apply the key zeroing fix in Agent signing code and proceed with Phase 3.

---

_Audit performed by: Security Review Process_  
_Next audit scheduled: Before production deployment_
