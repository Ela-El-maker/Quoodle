# 📱 Subsystem: Quoodle Mobile Client

**Component**: `quoodle-mobile-client`
**Type**: Flutter Application (Android / iOS)

---

## 1. Subsystem Purpose

### What it does
*   Acts as the **primary user interface** for the system administrator.
*   Scans QR codes to **pair** new devices.
*   Issues **commands** (e.g., "Lock Screen") to paired devices.
*   Visualizes real-time **telemetry** and **alerts**.

### What it explicitly does NOT do
*   It does **not** store the authoritative state of devices (Control Plane does that).
*   It does **not** communicate directly with Agents (always goes via Control Plane/Gateway).
*   It does **not** enforce policy (Control Plane rejects forbidden commands).

### Why it exists
To provide a secure, convenient "remote control" for the system that relies on cryptographic identity rather than just username/password.

---

## 2. Trust Model

### What it trusts
*   **Control Plane**: Trusted implicitly via TLS (HTTPS).
*   **User**: Trusts the local biometrics/PIN to unlock the app storage (Private Keys).

### What it does NOT trust
*   **The Network**: Assumes hostile network; uses strictly pinned TLS (roadmap).
*   **QR Codes**: Validates the format and signature of QR codes before processing.

### Boundaries & Assumptions
*   **Boundary**: Public Internet ↔ Mobile App.
*   **Assumption**: The device OS is not compromised (no jailbreak/root detection currently implemented).

---

## 3. Inputs & Outputs

### Inputs
*   **User Interaction**: Taps, swipes, biometric auth.
*   **Camera**: QR Code stream (Video).
*   **Push Notifications**: FCM/APNS payloads (JSON).
*   **API Responses**: HTTP/JSON from Control Plane.

### Outputs
*   **API Requests**: Signed HTTP/JSON requests.
*   **Visuals**: UI rendering of device state.

---

## 4. Internal Logic (High-Level)

### Core Responsibilities
1.  **Key Management**: Generate and store user ECDSA/Ed25519 keys in Secure Enclave (planned).
2.  **Session Management**: Handle JWT refresh flows.
3.  **Command Construction**: Create command intents with parameters.

### Workflows
*   **Pairing**:
    1.  User taps "Add Device".
    2.  Camera opens -> Scans QR.
    3.  Extracts `pair_token`.
    4.  POSTs to `/api/pair/confirm`.
*   **Command**:
    1.  User selects Device -> "Lock".
    2.  App checks local "sensitive" flag.
    3.  If sensitive, prompt Bio/PIN.
    4.  POST `/api/commands` with intent.

### Error Handling
*   **Offline**: Caches last known state; queues commands (roadmap) or blocks UI.
*   **Auth Failure**: Forces logout and wipe of session data.

---

## 5. Data Handling

*   **Storage**: `FlutterSecureStorage` for tokens and keys. SQLite/Hive for cached telemetry.
*   **Sensitive Data**: User credentials and Private Keys are never exported.
*   **Logging**: Local debug logs only (no centralized crash reporting yet).

---

## 6. Current State (Assessment)

### Working Features
*   [x] Basic UI scaffolding.
*   [x] API Client generation.
*   [x] Login flow (Happy path).

### Broken / Missing Features
*   [ ] **QR Scanning**: Camera integration is not implemented (Stubbed).
*   [ ] **Push Notifications**: No FCM integration.
*   [ ] **Offline Mode**: No local caching layer.
*   [ ] **Certificate Pinning**: Not implemented.

### Known Bugs
*   WebSocket connection logic is incomplete; does not handle reconnects gracefully.

---

## 7. Open Dependencies / Blockers

*   **Waiting on**: `quoodle-control-plane` to finalize the `pair_token` format in the QR code.
*   **Impact**: Cannot test pairing end-to-end without real tokens.

---

## 8. Testing

### Existing Coverage
*   Unit tests: ~10% (Models only).
*   UI Tests: None.

### Gaps
*   No integration tests with a mock backend.

### Risks
*   **App Store Rejection**: Due to high-risk permissions (Camera, Location) layout.
*   **Bio-bypass**: Logic for sensitive commands might be bypassed if not enforced on backend too.
