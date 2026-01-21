# Executive Summary (what it is, what state it’s in)
Quoodle is a research-grade, consent-based secure device control system that simulates an EMM/EDR stack for Windows endpoints. The JSON specs define a full end-to-end architecture: mobile client issues commands through a Laravel control plane, a FastAPI gateway routes them over WSS to a Windows agent, and a kernel service executes privileged operations with signed IOCTLs. Based on the repository implementation, several key paths are present (JWT auth, command dispatch, WSS protocol handling, webhook forwarding), but critical security and operational elements are simulated or partial (CA/CSR issuance, key rotation, policy hash, telemetry persistence, pairing/discovery binding). End-to-end flow is therefore blocked without manual seeding and placeholder features, and cannot be declared “DONE” under the spec requirements.

# System Architecture (diagram + narrative)
```mermaid
graph TD
  Mobile[quoodle-mobile-client] -->|REST /api/*| Laravel[quoodle-control-plane]
  Mobile -->|WSS/Push (spec)| Gateway[quoodle-gateway]
  Laravel -->|POST /api/v1/command/dispatch| Gateway
  Gateway -->|WSS /agent| Agent[quoodle-agent-windows]
  Agent -->|IOCTL| Kernel[quoodle-kernel-guard]
  Gateway -->|Webhooks /device/* /command/*| Laravel

  Laravel -->|MySQL| MySQL[(MySQL)]
  Laravel -->|Redis| Redis[(Redis)]
  Gateway -->|Redis streams| Redis
  Gateway -->|device_registry.db| DeviceReg[(Device Registry DB)]

  subgraph Trust Boundaries
    Laravel
    Gateway
    Agent
    Kernel
  end
```
Narrative:
- The Control Plane (Laravel) is the root of trust and policy authority; it issues JWTs, signs command envelopes, and records audit/compliance state.
- The Gateway (FastAPI) is a stateful WSS hub that verifies signatures, enforces replay protection, and forwards telemetry and command results to Laravel.
- The Windows Agent handles WSS connectivity, signature verification, and IOCTL requests to the kernel service.
- The Kernel Guard executes privileged opcodes and returns signed results.
- Primary data stores are MySQL (system of record), Redis (queues/streams), and a local device key registry used by the gateway.

# End-to-End User Flow Trace
Below is the intended flow from the JSON specs, with implementation notes and breakpoints based on repo evidence.

1) Register/Login
- Mobile → Laravel: `POST /api/register` and `POST /api/login` (Laravel_MobileApp_Interface).
- Implementation exists in `quoodle-control-plane/app/Http/Controllers/Auth/RegisterController.php` and `LoginController.php`.
- 2FA is spec’d but login path currently skips 2FA enforcement (`LoginController.php` TODO).

2) Pair Device
- Spec: Mobile → Laravel `POST /api/pair/init`, then `POST /api/pair/confirm` with `pair_token` from agent QR (Laravel_MobileApp_Interface; System flow.json).
- Implementation exists in `PairingController.php`, but `pair_token` is generated server-side and is not tied to an agent or discovery handshake. This breaks the binding to an actual Windows Agent identity.

3) Device Online (Agent → Gateway)
- Spec: Agent connects WSS `/agent`, sends `AUTH`, receives `AUTH_ACK`, and FastAPI posts `/device/online` webhook to Laravel (AgentFastAPIInterface; FastAPI_Laravel_Interface).
- Implementation exists in `quoodle-gateway/app/main.py` for WSS auth and in `quoodle-gateway/app/ws/webhooks.py` for webhook forwarding.
- Breakpoint: the gateway requires a device public key in its registry to verify signatures; pairing flow does not provision the agent key into Laravel or the gateway registry (`FastApiDeviceKeySync` exists but no pairing linkage).

4) Send Command
- Spec: Mobile → Laravel `POST /api/commands`; Laravel → FastAPI `POST /command/dispatch`; FastAPI → Agent `COMMAND_DELIVERY` (Laravel_MobileApp_Interface; FastAPI_Laravel_Interface; AgentFastAPIInterface).
- Implementation exists for command enqueue (`CommandController` + `CommandService`) and dispatch (`FastAPIDispatcher` + `quoodle-gateway/app/api_controller.py`).
- Breakpoint risk: Laravel dispatch requires `LARAVEL_SERVICE_PRIVATE_KEY_B64` configured, and FastAPI enforces `X-Laravel-Signature` if enabled. Missing keys/config will block dispatch.

5) Command Execution
- Spec: Agent verifies Laravel signature and sends IOCTL request to KernelService per AgentKernelInterface; kernel returns signed result.
- Implementation status is partial/unknown in this repo; the kernel driver code exists but spec coverage of all opcodes and signature verification cannot be confirmed from the available evidence.

6) Result Visible on Mobile
- Spec: Agent sends `COMMAND_RESULT` to FastAPI; FastAPI posts `/webhook/command/result` to Laravel; Mobile retrieves `GET /api/commands/{command_id}`.
- Implementation exists in `quoodle-gateway/app/ws/results.py` and `quoodle-control-plane/app/Http/Controllers/Webhooks/CommandResultWebhookController.php` and `CommandQueryController`.
- Breakpoint: depends on steps 3–5 working (agent auth, key provisioning, kernel execution).

Conclusion on end-to-end flow:
- End-to-end is currently blocked without manual seeding/configuration, because pairing does not bind agent identity and the gateway requires device keys to authenticate agents. Command execution also depends on kernel/agent alignment not proven by evidence.

# Working vs Missing (Truth Table)
| Capability | Evidence in spec | Implementation status (Unknown/Partial/Complete) | What’s missing | Blocking? |
|---|---|---|---|---|
| User register/login + JWT session | Laravel_MobileApp_Interface `POST /api/register`, `POST /api/login` | Partial | 2FA enforcement in login is TODO; key material must exist | No (basic login works) |
| Pairing flow with agent QR token | Laravel_MobileApp_Interface `POST /api/pair/init`, `POST /api/pair/confirm`; System flow.json pairing steps | Partial | Pair token not derived from agent/discovery; no device key binding | Yes |
| Agent discovery handshake | System flow.json `POST /api/discovery/confirm` | Missing | No discovery endpoints in FastAPI | Yes |
| Agent WSS auth + signature verification | AgentFastAPIInterface AUTH/AUTH_ACK | Partial | Requires device pubkey registry; depends on seed/sync | Yes |
| Laravel → FastAPI command dispatch signing | FastAPI_Laravel_Interface `POST /command/dispatch` | Partial | Requires service keys and signature config | Yes |
| Agent → Kernel IOCTL execution | AgentKernelInterface schema/opcodes | Unknown/Partial | Evidence of full opcode mapping and signature checks not confirmed | Yes |
| Telemetry persistence/analytics | Laravel_MobileApp_Interface telemetry; Missing System Components analytics | Partial | Telemetry worker logs only; analytics API not present | No (for commands), Yes (for telemetry completeness) |
| OTA update pipeline | FastAPI_Laravel_Interface `POST /update/deploy` | Partial | Kernel update validation and rollout enforcement not evidenced | Maybe |
| Policy engine API + command registry API | Missing System Components.json | Partial | In-process policy/registry exist; external APIs not implemented | No (if in-process only), Yes (if spec requires API) |
| Compliance evaluation API | Missing System Components.json | Partial | In-process checks exist; external API not implemented | No (if in-process only), Yes (if spec requires API) |

# Dummy/Simulated Hooks & Test Scaffolding
- Simulated CA chain and device certs: `quoodle-control-plane/app/Services/CA/CertificateAuthority.php` returns `root-ca-simulated` and base64 “CERT:” strings. Risk: no real device identity or revocation; gate by replacing with actual X.509 issuance and storage.
- CSR generation placeholders: `quoodle-control-plane/app/Services/CA/CSRGenerator.php` returns `csr-placeholder-*` and `private-key-placeholder`. Risk: device bootstrap not real; remove by generating real CSRs on agent.
- JWT key rotation placeholders: `quoodle-control-plane/app/Services/JWT/KeyRotationService.php` returns `public-key-placeholder`. Risk: JWKS rotation not real; replace with actual key store and rotation.
- Policy hash placeholder: `quoodle-agent-windows/src/policy/policy_bundle_cache.cpp` returns `sha256:policy-placeholder` and FastAPI command meta uses `policy-placeholder` in `quoodle-gateway/app/api_controller.py`. Risk: policy enforcement and audit anchors are meaningless.
- Telemetry persistence mock: `quoodle-gateway/app/workers/telemetry_worker.py` logs to stdout instead of storage. Risk: no durable telemetry or analytics.
- Signature fallback to sha256: `quoodle-gateway/app/ws/protocol.py` falls back to SHA256 if Ed25519 is not configured. Risk: breaks cryptographic integrity guarantees.
- Pairing token generated in Laravel: `PairingController.php` issues random tokens without agent-provided QR/auth. Risk: device binding is not to real agent identity.
- Simulated scripts and tests: `quoodle-agent-windows/scripts/*` (simulated install/build), `scripts/e2e_full_flow.py`, `quoodle-tools/srs/*` use placeholders and simulated data. Risk: false sense of readiness.

# Critical Gaps & Risks (Prioritized)
P0
- Symptom: Device identity and crypto chain are simulated.
  Cause: CA/CSR/key rotation placeholders; signature fallbacks.
  Fix: Implement real X.509 issuance, store keys securely, enforce Ed25519 with required config.
  Owner: Control Plane, Gateway, Agent/Kernel.
  Impact if not fixed: No real trust boundary; commands can be spoofed; audit chain invalid.
- Symptom: Pairing does not bind device to agent keys.
  Cause: Pair token issued by Laravel, not by agent; no discovery handshake.
  Fix: Implement discovery + QR token signed by agent; persist device pubkeys and sync to gateway.
  Owner: Agent, Gateway, Control Plane.
  Impact if not fixed: End-to-end chain cannot authenticate real devices.
- Symptom: Command execution trust not proven end-to-end.
  Cause: Kernel opcode coverage/signature checks not verified; agent-to-kernel mapping unknown.
  Fix: Implement IOCTL schema validation + signature verification; align opcodes with spec.
  Owner: Agent, Kernel Guard.
  Impact if not fixed: Commands may fail silently or execute unsafely.

P1
- Symptom: Telemetry pipeline does not persist data.
  Cause: Telemetry worker is a mock; analytics APIs missing.
  Fix: Implement Redis stream consumption and persistence + analytics endpoints.
  Owner: Gateway, Control Plane.
  Impact if not fixed: No reliable telemetry or compliance/risk scoring.
- Symptom: Service-to-service signature enforcement depends on config.
  Cause: Missing service keys or disabled enforcement.
  Fix: Provide mandatory config, health checks, and deployment validation.
  Owner: Control Plane, Gateway.
  Impact if not fixed: Command dispatch and webhooks can be spoofed.

P2
- Symptom: Mobile defaults to localhost endpoints and placeholder fingerprints.
  Cause: Hard-coded env config and placeholder identifiers.
  Fix: Environment configuration and secure device fingerprinting.
  Owner: Mobile client.
  Impact if not fixed: Misconfigured deployments, weak device binding.

# Definition of Done (DoD) Checklist
Functional
- Register/login + token refresh works end-to-end with valid JWTs; evidence: integration test logs and API responses.
- Pairing binds a real agent QR token to a device entry and registers agent pubkey; evidence: QR scan flow + device key in registry.
- Device online/offline updates are reflected in Control Plane; evidence: webhook logs and device state changes.
- Command dispatch, ack, and result visible on mobile; evidence: command lifecycle state transitions and audit log entries.

Security
- Ed25519 signatures enforced on all command envelopes and IOCTL requests; evidence: signature verification tests with failure cases.
- JWT validation uses JWKS and rejects expired/invalid tokens; evidence: negative tests + logs.
- Key management uses real keys (no placeholders); evidence: key store audit and configuration checks.

Reliability
- Agent reconnect backoff, offline queue, and DLQ behavior validated; evidence: fault-injection tests and metrics.
- Telemetry pipeline persists to durable storage and supports rollups; evidence: database entries and query results.

Observability
- Audit chain is append-only and queryable per device/command; evidence: audit records with hashes.
- Structured logs and metrics for gateway, control plane, agent, kernel; evidence: dashboards or log samples.

QA
- Unit and integration test suite for each component green; evidence: CI logs.
- End-to-end test script exercises full flow with real crypto; evidence: test report artifacts.

Docs
- Runbooks for local dev, staging, and recovery; evidence: updated docs with verified steps.
- API and protocol docs synced to the current implementation; evidence: versioned docs with change log.

# Improvement Plan / Roadmap
1) Trust and Identity Hardening (P0)
- Implement real CA/CSR handling and JWKS key rotation.
- Enforce Ed25519 signatures without fallback.
- Bind pairing tokens to agent-generated QR payloads and device public keys.
Dependencies: Agent QR generation, Control Plane CA, Gateway device key registry.
Exit criteria: Agent can authenticate with real keys; all signature checks enforced.

2) End-to-End Command Execution (P0)
- Validate IOCTL schema and opcode mapping end-to-end.
- Align agent-to-kernel command handling with AgentKernelInterface.
Dependencies: Kernel opcode coverage, agent IOCTL signing.
Exit criteria: Commands execute with signed IOCTL and verified results.

3) Telemetry and Analytics (P1)
- Implement telemetry persistence and analytics API from Missing System Components.
- Wire compliance/risk scoring with stored telemetry.
Dependencies: Redis stream workers, database schema, analytics service.
Exit criteria: Telemetry visible in UI with risk scores and history.

4) Production Readiness (P1/P2)
- Configuration validation, secret management, and environment profiles.
- Add runbooks, deployment validation, and smoke tests.
Dependencies: CI/CD updates, docs.
Exit criteria: clean staging deployment with full flow tests.

# Appendices
Assumptions:
- All components are intended to run in a controlled lab and remain consent-based.
- The JSON specs are authoritative for protocol and flow definitions.

Open questions:
- Which spec version is authoritative when v1 and v3 conflict?
- Are kernel opcode implementations complete and signed at build time?
- What is the intended source of the agent QR `pair_token` and how is it verified?
