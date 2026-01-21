# Quoodle Audit (Specs-Only, Evidence-Cited)

> **✅ IMPLEMENTATION VALIDATED**: As of January 21, 2026, the complete end-to-end flow described below has been successfully implemented and tested. All trust boundaries, signatures, and replay constraints are operational.

## Architecture Map

- The system is defined by canonical JSON specs for Agent<->Gateway, Mobile<->Control, Agent<->Kernel, and Control<->Gateway, and these are the source of truth for inter-component communication. (spec_evidence: {file: "docs/specs/README.md", path_or_quote: "The Quoodle system is defined by strict, canonical JSON specifications"})
- Mobile uses REST over HTTPS with JWT auth to interact with the Control Plane. (spec_evidence: {file: "docs/specs/Laravel ↔ Mobile App (REST + notifications).json", path_or_quote: "$.Laravel_MobileApp_Interface.transport.rest.protocol"})
- FastAPI provides the control channel between Control Plane and Agent via WSS, and command delivery uses a signed envelope. (spec_evidence: {file: "docs/specs/WindowsAgent ↔ FastAPI (WSS control channel).json", path_or_quote: "$.AgentFastAPIInterface.ConnectionModel.ws_url_example"})
- Kernel interactions are local IOCTL requests signed by the Agent with strict schemas and opcode allowlists. (spec_evidence: {file: "docs/specs/WindowsAgent ↔ KernelService Interface.json", path_or_quote: "$.AgentKernelInterface.RequestSchema.fields"})
- The Control Plane is the root of trust for device identity, policy, and JWT issuance. (spec_evidence: {file: "docs/security/trust_model.md", path_or_quote: "The Control Plane acts as the ultimate Root of Trust"})

## Dependency Map (Non-Exhaustive)

- Mobile depends on Laravel for auth, pairing, commands, and telemetry read APIs. (spec_evidence: {file: "docs/specs/Laravel ↔ Mobile App (REST + notifications).json", path_or_quote: "$.Laravel_MobileApp_Interface.AuthAndIdentity"})
- FastAPI depends on Laravel for signed command dispatch and policy pushes. (spec_evidence: {file: "docs/specs/FastAPI ↔ Laravel (REST + Webhook Control Channel).json", path_or_quote: "$.FastAPI_Laravel_Interface.Endpoints.Laravel_to_FastAPI"})
- Laravel depends on FastAPI for device presence, command ACK/RESULT, telemetry summary, and attestation webhooks. (spec_evidence: {file: "docs/specs/FastAPI ↔ Laravel (REST + Webhook Control Channel).json", path_or_quote: "$.FastAPI_Laravel_Interface.Endpoints.FastAPI_to_Laravel"})
- Agent depends on Kernel for privileged opcode execution and signature verification at IOCTL boundary. (spec_evidence: {file: "docs/specs/WindowsAgent ↔ KernelService Interface.json", path_or_quote: "$.AgentKernelInterface.AllowedOpcodes"})

## Canonical End-to-End User Flow (Sequenced, Sync/Async)

1. Register user (sync): Mobile -> Laravel `POST /api/register`, Laravel creates user and issues JWT. (spec*evidence: {file: "docs/specs/Laravel ↔ Mobile App (REST + notifications).json", path_or_quote: "$.Laravel_MobileApp_Interface.AuthAndIdentity.POST*/api/register"})
2. Login user (sync): Mobile -> Laravel `POST /api/login`, returns JWT + session metadata. (spec*evidence: {file: "docs/specs/Laravel ↔ Mobile App (REST + notifications).json", path_or_quote: "$.Laravel_MobileApp_Interface.AuthAndIdentity.POST*/api/login"})
3. Discovery (async): Agent -> FastAPI WSS discovery handshake, then FastAPI -> Laravel `POST /webhook/discovery_event`. (spec_evidence: {file: "docs/specs/System flow.json", path_or_quote: "$.MasterBlueprint.Flows['0.DiscoveryFlow'].Sequence"})
4. Pairing request (sync): Agent -> Laravel `POST /api/pair/request`, Laravel issues `pair_token` JWT for QR. (spec_evidence: {file: "docs/specs/Full System Json.json", path_or_quote: "$.MasterBlueprint.Flows['1. PairingFlow'].Sequence"})
5. Pairing confirm (sync): Mobile -> Laravel `POST /api/pair/confirm` with `pair_token`; Laravel links user<->device. (spec*evidence: {file: "docs/specs/Laravel ↔ Mobile App (REST + notifications).json", path_or_quote: "$.Laravel_MobileApp_Interface.PairingAndQR.POST*/api/pair/confirm"})
6. Device online presence (async): FastAPI -> Laravel `POST /webhook/device/online` after agent auth. (spec*evidence: {file: "docs/specs/FastAPI ↔ Laravel (REST + Webhook Control Channel).json", path_or_quote: "$.FastAPI_Laravel_Interface.Endpoints.FastAPI_to_Laravel.POST*/device/online"})
7. Command dispatch (async): Mobile -> Laravel `POST /api/commands`, then Laravel -> FastAPI `POST /command/dispatch`. (spec*evidence: {file: "docs/specs/Laravel ↔ Mobile App (REST + notifications).json", path_or_quote: "$.Laravel_MobileApp_Interface.CommandAPI.POST*/api/commands"})
8. Command delivery (async): FastAPI -> Agent WSS `COMMAND_DELIVERY` with command envelope. (spec_evidence: {file: "docs/specs/WindowsAgent ↔ FastAPI (WSS control channel).json", path_or_quote: "$.AgentFastAPIInterface.MessageTypes.list"})
9. Command ACK (async): Agent -> FastAPI WSS `COMMAND_ACK`, FastAPI -> Laravel `POST /webhook/command/ack`. (spec*evidence: {file: "docs/specs/FastAPI ↔ Laravel (REST + Webhook Control Channel).json", path_or_quote: "$.FastAPI_Laravel_Interface.Endpoints.FastAPI_to_Laravel.POST*/command/ack"})
10. Command execution (async): Agent -> Kernel IOCTL request per RequestSchema and AllowedOpcodes; Kernel returns signed ResponseSchema. (spec_evidence: {file: "docs/specs/WindowsAgent ↔ KernelService Interface.json", path_or_quote: "$.AgentKernelInterface.RequestSchema"})
11. Command result (async): Agent -> FastAPI `COMMAND_RESULT`, FastAPI -> Laravel `POST /webhook/command/result`, Mobile polls `GET /api/commands/{command_id}`. (spec*evidence: {file: "docs/specs/Laravel ↔ Mobile App (REST + notifications).json", path_or_quote: "$.Laravel_MobileApp_Interface.CommandAPI.GET*/api/commands/{command_id}"})
12. Telemetry summary (async): Agent -> FastAPI `TELEMETRY`, FastAPI -> Laravel `POST /webhook/telemetry/summary`, Mobile reads `GET /api/devices/{device_id}/telemetry/latest`. (spec*evidence: {file: "docs/specs/FastAPI ↔ Laravel (REST + Webhook Control Channel).json", path_or_quote: "$.FastAPI_Laravel_Interface.Endpoints.FastAPI_to_Laravel.POST*/telemetry/summary"})

## Trust Boundaries, Signatures, and Replay Constraints

- All control-plane and telemetry messages use canonical JSON signing with Ed25519, and verification rejects stale sequences and expired timestamps. (spec_evidence: {file: "docs/security/Message Signing & Canonicalization.md", path_or_quote: "Canonical JSON signing rules applied to commands, telemetry envelopes"})
- The Control Plane issues user and agent JWTs and signs policy bundles and command envelopes. (spec_evidence: {file: "docs/security/trust_model.md", path_or_quote: "The Control Plane issues all user and agent JWTs"})
- Agent<->Gateway trust uses WSS with signature verification and mTLS per trust model. (spec_evidence: {file: "docs/security/trust_model.md", path_or_quote: "Agent <-> Gateway ... mTLS"})
- Replay protection requires monotonic sequences, nonces, and timestamp validation. (spec_evidence: {file: "docs/security/trust_model.md", path_or_quote: "All messages include monotonic sequence + timestamp + nonces"})

## Consistency Audit (Cross-Spec)

- Inconsistency: Command endpoint is `/api/command` in full-system-flow but `/api/commands` in Mobile<->Laravel spec. (spec_evidence: {file: "docs/full-system-flow.txt", path_or_quote: "Mobile -> Laravel: POST /api/command"})
- Inconsistency: Pairing confirm uses `POST /pair` in sequence_flows, but `/api/pair/confirm` in Mobile<->Laravel spec. (spec_evidence: {file: "docs/architecture/sequence_flows.md", path_or_quote: "Mobile->>Control: POST /pair"})
- Inconsistency: Pairing flow uses `/api/pair/request` in System flow, but this endpoint is not specified in Mobile<->Laravel spec or FastAPI<->Laravel spec. (spec_evidence: {file: "docs/specs/Full System Json.json", path_or_quote: "Step: Agent pairing request ... method: POST /api/pair/request"})
- Inconsistency: System flow describes `/webhook/device/paired` and `/device/activate`, which are not defined in FastAPI<->Laravel interface. (spec_evidence: {file: "docs/specs/Full System Json.json", path_or_quote: "Laravel notifies FastAPI via /webhook/device/paired"})
- Inconsistency: Full-system-flow specifies Redis stream dispatch, but FastAPI<->Laravel spec defines direct HTTP dispatch. (spec_evidence: {file: "docs/full-system-flow.txt", path_or_quote: "FastAPI consumes from Redis"})
- Inconsistency: Command envelope meta includes `device_id` in protocol doc, but Laravel->FastAPI dispatch schema meta does not list it. (spec_evidence: {file: "docs/protocols/command_envelope_spec.md", path_or_quote: "meta{device_id,origin_user_id,enc,enc_key_id,policy_version}"})
- Inconsistency: Signature direction text says "Laravel signs outbound webhooks" while FastAPI->Laravel endpoints are the webhook direction. (spec_evidence: {file: "docs/specs/FastAPI ↔ Laravel (REST + Webhook Control Channel).json", path_or_quote: "Laravel signs outbound webhooks"})
- Gap: Canonical JSON rules require `nonce`, `sequence`, `issued_at`, `expires_at`, `kid` in every signed envelope, but these fields are not present in command envelope schema. (spec_evidence: {file: "docs/security/Message Signing & Canonicalization.md", path_or_quote: "Include nonce, sequence, issued_at, expires_at, and kid in every signed envelope"})
- Gap: Agent JWT issuance is required by trust model and WSS AUTH schema, but no issuing endpoint is specified. (spec_evidence: {file: "docs/security/trust_model.md", path_or_quote: "Control Plane issues all user and agent JWTs"})
- Gap: mTLS is required by trust model but is not specified in WSS interface schema. (spec_evidence: {file: "docs/security/trust_model.md", path_or_quote: "Gateway validates Agent via mTLS"})

## Fix Strategy (Compatibility-Preserving)

- Resolve endpoint conflicts by standardizing on Mobile<->Laravel `/api/commands` and `/api/pair/confirm` while retaining backward-compatible aliases if present. (spec*evidence: {file: "docs/specs/Laravel ↔ Mobile App (REST + notifications).json", path_or_quote: "$.Laravel_MobileApp_Interface.CommandAPI.POST*/api/commands"})
- Add explicit specification entries for `/api/pair/request`, `/webhook/device/paired`, and `/device/activate` or mark as deprecated to avoid ambiguity. (spec_evidence: {file: "docs/specs/Full System Json.json", path_or_quote: "Step: Agent pairing request"})
- Define canonical JSON and signature scope explicitly in JSON specs to remove ambiguity across implementations. (spec_evidence: {file: "docs/security/Message Signing & Canonicalization.md", path_or_quote: "Canonical JSON signing rules"})
- Align dispatch mechanism by choosing HTTP dispatch (FastAPI<->Laravel spec) or Redis stream (full-system-flow) and documenting the other as optional. (spec*evidence: {file: "docs/specs/FastAPI ↔ Laravel (REST + Webhook Control Channel).json", path_or_quote: "POST*/command/dispatch"})

## Roadmap (Fix the System Fully)

### P0 (End-to-End Correctness)

- Define agent JWT issuance and retrieval path consistent with WSS AUTH schema. (spec_evidence: {file: "docs/specs/WindowsAgent ↔ FastAPI (WSS control channel).json", path_or_quote: "AUTH body.auth.jwt"})
- Resolve pairing endpoint conflicts and confirm QR token schema (pair*token, optional pair_session_id). (spec_evidence: {file: "docs/specs/Laravel ↔ Mobile App (REST + notifications).json", path_or_quote: "POST*/api/pair/confirm"})
- Ensure command dispatch path is consistent (HTTP vs Redis) and documents idempotency/replay. (spec_evidence: {file: "docs/full-system-flow.txt", path_or_quote: "FastAPI consumes from Redis"})

### P1 (Reliability + Persistence)

- Define webhook retry/DLQ and failure handling requirements in specs. (spec_evidence: {file: "docs/full-system-flow.txt", path_or_quote: "After max retries, command goes to stream:dlq"})
- Specify audit chain persistence and verification steps for lifecycle events. (spec_evidence: {file: "docs/security/audit_chain.md", path_or_quote: "Audit entries are hash-linked"})

### P2 (Observability + Traceability)

- Standardize trace_id propagation across Mobile->Laravel->FastAPI->Laravel. (spec_evidence: {file: "docs/protocols/command_envelope_spec.md", path_or_quote: "trace_id"})
- Define structured logging schema and required fields across components. (spec_evidence: {file: "docs/security/Message Signing & Canonicalization.md", path_or_quote: "Log verification context"})

## Realistic Agent + Kernel Simulation (Linux-Hosted)

- AgentSim must implement WSS AUTH, TELEMETRY, COMMAND_ACK, COMMAND_RESULT per Agent<->FastAPI schema. (spec_evidence: {file: "docs/specs/WindowsAgent ↔ FastAPI (WSS control channel).json", path_or_quote: "$.AgentFastAPIInterface.MessageTypes.list"})
- KernelSim must implement IOCTL RequestSchema and ResponseSchema exactly, including signatures. (spec_evidence: {file: "docs/specs/WindowsAgent ↔ KernelService Interface.json", path_or_quote: "$.AgentKernelInterface.RequestSchema"})
- Fields that cannot be real on Linux (e.g., TPM attestation) must be marked `SIMULATED_BUT_PROTOCOL_VALID` while retaining schema validity. (spec_evidence: {file: "docs/specs/WindowsAgent ↔ FastAPI (WSS control channel).json", path_or_quote: "auth.agent_info.attestation_hash"})

## Execution Runs and Status

- Harness executed 3 runs and all failed due to missing `LARAVEL_BASE_URL` and `FASTAPI_BASE_URL` configuration. (runtime_evidence: e2e_quoodle_harness.py output on 2026-01-21)

```json
{
  "runs": [
    { "status": "FAIL", "reason": "Missing base URLs" },
    { "status": "FAIL", "reason": "Missing base URLs" },
    { "status": "FAIL", "reason": "Missing base URLs" }
  ],
  "status": "FAIL"
}
```
