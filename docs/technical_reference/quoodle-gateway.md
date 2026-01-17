# 🔌 Subsystem: Quoodle Gateway

**Component**: `quoodle-gateway`
**Type**: FastAPI Application (Python / AsyncIO)

---

## 1. Subsystem Purpose

### What it does
*   **Connection Hub**: Terminates thousands of persistent WebSocket connections from Agents.
*   **Router**: Routes signed command envelopes from Control Plane -> Agent.
*   **Ingestor**: Receives high-volume telemetry from Agents -> Redis.

### What it explicitly does NOT do
*   It does **not** sign commands (it has no signing keys).
*   It does **not** make policy decisions (it is a dumb pipe).
*   It does **not** store persistent device state (it queries Control Plane or Redis).

### Why it exists
To offload the stateful, long-lived connection management from the synchronous PHP/Laravel backend. Python/AsyncIO is better suited for C10k concurrency.

---

## 2. Trust Model

### What it trusts
*   **Control Plane**: Trusts commands signed by the backend (verifies signature).
*   **Agent**: Trusts agents that present a valid, non-revoked mTLS certificate.

### What it does NOT trust
*   **Payload Contents**: It validates the *structure* (JSON schema) but treats the body as opaque/untrusted until signed.

### Boundaries
*   **Public Interface**: WSS `:8000/agent`.
*   **Internal Interface**: REST `:8000/command/dispatch` (protected by internal signature).

---

## 3. Inputs & Outputs

### Inputs
*   **WSS Stream**: `HEARTBEAT`, `TELEMETRY`, `COMMAND_RESULT`.
*   **REST**: `POST /dispatch` (from Control Plane).

### Outputs
*   **WSS Stream**: `COMMAND_DELIVERY`, `UPDATE_ANNOUNCE`.
*   **Redis**: Telemetry streams.
*   **Webhooks**: HTTP POSTs back to Control Plane.

---

## 4. Internal Logic (High-Level)

### Core Responsibilities
1.  **Connection Lifecycle**:
    *   Accept WSS.
    *   Perform mTLS handshake (handled by reverse proxy or internal SSL context).
    *   Wait for `AUTH` message.
    *   Map `SessionID` -> `WebSocket`.
2.  **Dispatch**:
    *   Receive Command Envelope.
    *   Lookup active socket for `device_id`.
    *   `await websocket.send_json(envelope)`.
3.  **Telemetry Pipeline**:
    *   `await websocket.receive_json()`.
    *   Validation.
    *   `redis.xadd("telemetry_stream", data)`.

### Error Handling
*   **Socket Drop**: Clean up connection map; notify Control Plane via webhook (`device_offline`).
*   **Backpressure**: If Redis is full, drop telemetry (prioritize command traffic).

---

## 5. Current State (Assessment)

### Working Features
*   [x] Basic WSS echo handler.
*   [x] Startup/Shutdown logic.

### Broken / Missing Features
*   [ ] **Workers**: Background workers for processing Redis streams are empty stubs.
*   [ ] **Redis Integration**: Currently mocking Redis; strictly in-memory.
*   [ ] **Signature Verification**: Does not verify signatures on inbound commands from Laravel yet.

---

## 6. Open Dependencies / Blockers

*   **Blocked by**: `quoodle-agent-windows` reconnect logic (flaky connections make gateway testing hard).

---

## 7. Risks & Failure Modes

*   **Thundering Herd**: If 10k agents disconnect and reconnect simultaneously, the Gateway might crash. Reconnect backoff is enforced on Agent, but Gateway needs rate limiting.
*   **Memory Leak**: Long-running Python AsyncIO loops are prone to accumulating garbage if closures aren't careful.
