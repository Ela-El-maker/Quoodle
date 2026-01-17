# 🚀 Recommendations

**Priority Scheme**:
*   🔴 **Immediate**: Fix now or system is unsafe/unusable.
*   🟡 **Short-term**: Fix before Beta release.
*   🟢 **Long-term**: Production hardening.

---

## 1. Immediate Fixes (High Risk / Low Effort)

1.  🔴 **Enable Use-Mode Signature Verification** (`Agent`)
    *   **Action**: Uncomment/Implement the Ed25519 verify step in the Agent's command loop.
    *   **Why**: Without this, the system is insecure.
2.  🔴 **Wire Kernel Opcodes** (`Kernel`)
    *   **Action**: Add the `case` statements for the remaining 12 opcodes in `quoodle-kernel-guard` dispatcher.
    *   **Why**: The system functionality is 85% broken (features don't work).
3.  🔴 **Protect Control Plane API** (`Control Plane`)
    *   **Action**: Add `auth:api` middleware to Laravel routes.
    *   **Why**: Prevents unauthorized command injection.

---

## 2. Short-Term Improvements (Q1 Roadmap)

*   🟡 **Implement Reconnection Backoff** (`Agent`): Prevent DDoS-ing the gateway during intermittent network failures.
*   🟡 **Redis Persistence** (`Gateway`): Move from in-memory queues to real Redis streams to survive gateway restarts.
*   🟡 **QR Scanning** (`Mobile`): Implement the camera plugin to allow real pairing.

---

## 3. Testing & Documentation Priorities

*   **Test Priority 1**: **End-to-End Command Loop**. Script a test that injects a command at the Control Plane and verifies the output at the Agent.
*   **Doc Priority 1**: **Developer Onboarding**. The `README.md` files are better now, but a "Getting Started" guide for a new dev to bring up the full stack locally (Docker Compose) is missing.

---

## 4. Architecture Alignments

*   **Mismatch**: The architecture claims "Attestation", but the Kernel returns stub data.
    *   *Recommendation*: Rename the feature to "Attestation (Simulated)" in docs until TPM integration is real.
*   **Mismatch**: The Trust Model claims "Certificate Pinning", but Mobile doesn't implement it.
    *   *Recommendation*: Add to the "Critical Gaps" list.
