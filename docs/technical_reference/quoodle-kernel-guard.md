# 🛡️ Subsystem: Quoodle Kernel Guard

**Component**: `quoodle-kernel-guard`
**Type**: Windows Kernel Driver (`.sys` / KMDF)

---

## 1. Subsystem Purpose

### What it does
*   **Privileged Execution**: Performs sensitive actions (Reboot, Lock, Terminate Process) in Ring 0.
*   **Tamper Resistance**: Protects the Agent process/registry keys from local modification.
*   **Attestation**: Reports the state of the system/boot chain (simulated TPM).

### What it explicitly does NOT do
*   It does **not** talk to the network.
*   It does **not** parse complex policy (it enforces simple opcodes).

### Why it exists
To provide a hardware-rooted (or at least kernel-rooted) anchor for the system. User-mode agents can always be killed by local admins or malware; kernel drivers are much harder to dislodge.

---

## 2. Trust Model

### What it trusts
*   **Agent**: Trusts inputs from the Agent *if and only if* they are signed by the Agent's private key (preventing other processes from spoofing IOCTLs).

### What it does NOT trust
*   **User Space**: General user space is treated as hostile.
*   **The Agent (Partially)**: Checks signatures to ensure the Agent hasn't been confused/hijacked by a non-owner.

---

## 3. Inputs & Outputs

### Inputs
*   **IOCTL**: Buffer containing {Opcode, Params, Signature}.

### Outputs
*   **IOCTL Output**: Buffer containing {Result, KernelSignature}.

---

## 4. Internal Logic (High-Level)

### Core Responsibilities
1.  **DriverEntry**: Create Device Object `\Device\QuoodleKernel`.
2.  **Dispatch**: Handle `IRP_MJ_DEVICE_CONTROL`.
3.  **Opcode Switch**:
    *   `EXEC_REBOOT`: Call `ZwInitiatePowerAction`.
    *   `EXEC_LOCK`: Call proprietary internal APIs or inject SAS sequence.
    *   `STAGE_UPDATE`: Write to protected file path.

### Error Handling
*   **Validation Fail**: Return `STATUS_INVALID_PARAMETER`.
*   **Exception**: Wrap all code in `__try / __except` to prevent BSOD.

---

## 5. Current State (Assessment)

### Working Features
*   [x] Driver Skeleton.
*   [x] Basic IOCTL Dispatcher.

### Broken / Missing Features
*   [ ] **Dispatcher**: Wired for only 2/14 opcodes (Critical Gap #1).
*   [ ] **Compilation**: `CMakeLists.txt` missing source files (Critical Gap #2).
*   [ ] **Attestation**: Returns stub data only.
*   [ ] **Tamper Check**: Uses hardcoded hashes.

### Known Technical Debt
*   Using deprecated WDM APIs in some places instead of WDF.

---

## 6. Open Dependencies / Blockers

*   **None**: It is the bottom of the stack.

---

## 7. Risks & Failure Modes

*   **BSOD**: A bug in the driver crashes the whole OS.
*   **Rootkit Behavior**: If the tamper protection is too aggressive, it might flag legitimate AV software or Updates as attacks.
