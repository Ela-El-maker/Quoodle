# Quoodle AI Agents Architecture Strategy

## 1) Core Thesis
Quoodle should adopt AI as an operational intelligence copilot, never as a trust anchor: AI agents should help operators and security teams understand risk, triage events, and prepare actions faster, while deterministic control remains in the existing security chain (`quoodle-mobile-client -> quoodle-control-plane -> quoodle-gateway -> quoodle-agent-* -> quoodle-kernel-guard`). In this model, AI improves decision speed and quality, but never owns authorization, cryptographic authority, command validity, replay enforcement, or privileged execution.

## 2) Current System Anchors and Non-Negotiables
### System anchors (current state)
- `quoodle-control-plane` (Laravel) is the root of trust and governance authority: IdP, CA, policy authority, command authorization, and audit authority.
- `quoodle-gateway` (FastAPI) is the real-time transport and enforcement layer for WSS routing, signature checks, replay/TTL handling, quarantine gating, and telemetry/result relay.
- `quoodle-agent-linux` and `quoodle-agent-windows` are endpoint execution mediators: verify signatures and forward to privileged runtime.
- `quoodle-kernel-guard` / Linux privileged daemon is privileged execution and low-level enforcement boundary.

### Non-negotiables
- AI is never a source of truth for identity, policy, command authorization, quarantine state, or execution state.
- AI cannot sign production command envelopes or operate CA/JWT/signing keys.
- AI cannot bypass `PolicyEvaluator`, replay protection, or command dispatch controls.
- AI cannot directly trigger privileged execution paths (IOCTL/daemon calls).

## 3) Quoodle Agent Taxonomy
- **Operator assistants**: interactive helpers in mobile/control-plane workflows that summarize context and draft safe next steps.
- **Workflow copilots**: bounded assistants that prepare policy/compliance/risk assessments before human approval.
- **Background analyzers**: asynchronous analytics workers correlating telemetry, command outcomes, attestation, and audit chains.
- **Decision-support systems**: scored recommendations with confidence and evidence references for SOC/operator decisions.
- **Narrowly-scoped automations**: low-risk, reversible automations (for example summarization, ticket classification, enrichment) with no cryptographic or privileged authority.

## 4) Where Agents Fit Best in Quoodle
### Mobile operator experience
- Preflight command risk explanation before `/api/commands` submission.
- Device state summarization for faster operator decisions.
- Incident-context cards during high-severity alerts.

### SOC/security operations
- Cross-signal anomaly triage from telemetry, attestation, command failures, and quarantine transitions.
- Priority scoring for investigation queues.
- Incident timeline reconstruction and evidence packaging.

### Command governance
- Command intent risk scoring and policy-conflict hints before execution.
- Sensitive command review recommendations (2FA/escalation required).
- Post-command verification advisory (expected telemetry deltas, follow-up checks).

### Compliance and audit operations
- Audit-chain forensic summarization and gap detection.
- Compliance evidence preparation for audit exports.
- Drift detection between policy definitions and observed behavior.

### Release/update operations
- OTA rollout risk forecasting by cohort/device posture.
- Candidate quarantine recommendations when update failures correlate with risk signals.

### Infra and monitoring
- Alert deduplication and root-cause clustering.
- Monitoring narrative generation for on-call handoff.

## 5) Quoodle Agent Roles (Concrete Map)
| Agent | Mission | Inputs | Outputs | Trigger | Action Authority | Must Never Do |
|---|---|---|---|---|---|---|
| Command Risk Advisor | Score and explain risk before command dispatch | `/api/commands` payload, device state, policy context, recent telemetry | Risk score, recommended safeguards, approval flags | Operator command preflight | Recommend only | Authorize/dispatch command |
| Policy Drift Analyst | Detect divergence between policy intent and observed outcomes | Policy profiles, command outcomes, compliance checks, telemetry trends | Drift reports with affected cohorts and likely causes | Scheduled (hourly/daily) | Recommend only | Change policy or push policy bundles |
| Telemetry Anomaly Triage Agent | Correlate suspicious telemetry patterns and prioritize cases | Telemetry summaries, baseline profiles, recent command history, alerts | Triage queue, anomaly class, confidence, context refs | Event-driven on telemetry/alerts | Low-risk case labeling only | Quarantine or block execution directly |
| Quarantine Recommendation Agent | Recommend quarantine or release decisions with evidence | Risk signals, attestation status, policy sync state, command failures | `recommend_quarantine` or `recommend_release` with rationale | Event-driven + scheduled review | Recommend only; optional low-risk notification drafts | Change quarantine state directly |
| Incident Timeline Builder | Build incident timelines for investigation and response | Audit chain, command ack/result, device online/offline events, telemetry | Ordered timeline, causal hypotheses, evidence bundle | Manual investigator request or critical incident | Artifact generation only | Edit audit records |
| Update Rollout Risk Agent | Predict rollout risk and suggest staged deployment rules | OTA metadata, device cohorts, past update failures, compliance posture | Risk heatmap, rollout policy suggestions | Before `/api/v1/update/deploy` | Recommend only | Deploy or rollback updates |
| Attestation Signal Correlator | Correlate attestation failures with broader compromise indicators | Attestation webhooks, device lifecycle, command anomalies | Compromise-likelihood score and triage references | Event-driven on attestation events | Recommend only | Revoke certificates/keys |
| Audit Chain Forensics Assistant | Surface anomalies and chain integrity concerns for auditors | Audit trail hashes, append patterns, command lifecycle refs | Forensics report and verification checklist | Scheduled + on-demand audit | Report generation only | Mutate audit chain entries |
| Operator Workflow Copilot | Reduce operator cognitive load in daily fleet operations | Device detail, command history, telemetry latest, active alerts | Next-best action suggestions, procedural checklist | Interactive in mobile/control plane | Suggestion-only UI assistance | Execute disruptive actions |
| Compliance Evidence Assembler | Build structured evidence packets for compliance reviews | Compliance profiles, policy evaluations, command outcomes, attestations | Export-ready evidence package with traceability links | Scheduled reporting + manual export | Packaging only | Mark device compliant/non-compliant authoritatively |

## 6) Hard No-Go Boundaries
AI agents must not own or directly perform any of the following:
- CA lifecycle operations and private key usage.
- JWT issuance, refresh authority, or session invalidation decisions.
- Final command authorization and cryptographic command signing.
- Replay/nonce/TTL enforcement decisions.
- Quarantine state changes without deterministic policy and explicit approval.
- Kernel allowlist enforcement or privileged execution routing.
- Audit-chain mutation or deletion.
- Certificate revocation, device identity trust, or trust-anchor changes.

Rationale: these are cryptographic and deterministic security controls; probabilistic systems must not become authority in those paths.

## 7) Integration Architecture and Runtime Flow
### Architecture boundaries
- Laravel (`quoodle-control-plane`) remains business/security authority.
- FastAPI (`quoodle-gateway`) remains transport/enforcement authority for live routing.
- Agent intelligence layer is sidecar analytics + recommendation services consuming approved events and read models.
- AI outputs are advisory artifacts with evidence references and confidence; actions require deterministic APIs and approval gates.

### Runtime shape
```text
Operator (Mobile)
   |
   v
quoodle-control-plane (Laravel: auth/policy/audit/command auth)
   |\
   | \__ deterministic dispatch -> quoodle-gateway (FastAPI WSS/replay/quarantine)
   |                               |
   |                               v
   |                         quoodle-agent-* -> quoodle-kernel-guard
   |
   +--> Agent Intelligence Sidecar (read-only event/context)
            |
            +--> Recommendation artifacts (risk/triage/timeline)
            |
            +--> Approval-gated action requests -> control-plane APIs
```

### Communication flow
1. Control-plane and gateway emit command, telemetry, attestation, and lifecycle events to an internal context stream/store.
2. AI sidecar reads scoped context and computes recommendations.
3. Recommendation is written as immutable artifact with confidence, context references, and rationale summary.
4. Operator/SOC reviews recommendation in UI.
5. If approved, control-plane executes deterministic workflow (`/api/commands`, policy evaluation, dispatch, audit append).
6. Outcome is logged and tied back to recommendation ID for traceability.

## 8) Interaction Model (Conservative Autonomy)
### Suggestion-only
- Command preflight risk analysis.
- Telemetry anomaly explanations.
- Incident timeline assembly.
- Update rollout advice.

### Approval-required
- Any recommendation that could lead to disruptive actions (quarantine, sensitive command classes, fleet-wide changes).
- Any recommendation that changes risk posture or compliance interpretation.

### Low-risk autonomous background tasks
- Alert/incident summarization.
- Context enrichment and classification.
- Evidence packet assembly.
- Narrative generation for handoff/reporting.

No autonomous pathway may bypass policy enforcement, cryptographic verification, or privileged execution boundaries.

## 9) Proposed Internal Interfaces (Documentation Spec)
### 9.1 Recommendation envelope
```json
{
  "recommendation_id": "rec_01J...",
  "device_id": "dev_abc123",
  "context_refs": [
    "cmd:6e7f...",
    "telemetry:2026-03-30T11:03:00Z",
    "audit:chain:hash:..."
  ],
  "risk_score": 0.82,
  "recommended_action": "require_manual_review_and_quarantine_candidate",
  "confidence": 0.77,
  "reasoning_summary": "attestation mismatch + repeated high-risk command failures + policy drift",
  "required_approvals": ["soc_operator", "security_admin"]
}
```

### 9.2 Approval-state contract
```text
proposed -> approved/rejected -> executed -> verified
```
- `proposed`: AI artifact created.
- `approved/rejected`: human decision with actor and timestamp.
- `executed`: deterministic system action taken via control-plane/gateway path.
- `verified`: post-action state validated (telemetry/compliance/audit).

### 9.3 Event inputs for agent context
- Command lifecycle events: queued, dispatched, acked, completed, failed, expired.
- Telemetry summaries and risk signals.
- Attestation events and verification outcomes.
- Quarantine transitions and reason codes.
- Audit chain references and integrity checks.

## 10) Safety and Guardrails
- **Permission-scoped tools**: each agent has explicit allowlist; default deny.
- **No key access**: AI services cannot read or use signing private keys.
- **Approval gates**: disruptive outcomes require human approval and role checks.
- **Confidence thresholds**: low-confidence outputs auto-route to manual review.
- **Immutable traceability**: store prompt/context hash, tool calls, recommendation payload, and approval outcomes.
- **Prompt injection resilience**: treat telemetry/artifacts as untrusted; isolate and sanitize before reasoning.
- **PII/secret minimization**: redact non-essential identifiers and secrets from AI context.
- **Rollback/override**: every AI-influenced executed action has a deterministic override path and accountable actor.
- **Rate and blast-radius limits**: cap recommendations/actions per device/tenant/time window.

## 11) Testing Strategy
### Behavior and tool contracts
- Golden tests for recommendation quality and structured output validity.
- Contract tests for recommendation envelope schema and approval-state transitions.
- Tool-permission tests proving disallowed operations fail closed.

### Security and adversarial testing
- Red-team scenarios: forged telemetry, replay-like sequences, command/result poisoning, context contamination.
- Injection tests against summarization and triage pipelines.
- Drift tests to detect model regressions in risk scoring or recommendation consistency.

### Workflow and operational testing
- Shadow mode against live-like streams with no action authority.
- Replay tests over historical incidents.
- Human review sampling with precision/recall tracking for triage quality.
- Failure-injection tests for missing/stale context, webhook delays, and partial outages.

## 12) Rollout Plan
### Phase 1: Assistive only
- Ship Command Risk Advisor + Incident Timeline Builder in suggestion-only mode.
- Success: reduced mean decision latency, higher operator confidence, no policy bypass incidents.

### Phase 2: Workflow copilot
- Add Telemetry Anomaly Triage Agent + Compliance Evidence Assembler.
- Success: triage throughput increase, improved incident prioritization quality.

### Phase 3: Constrained automation
- Enable low-risk autonomous summarization/classification and routing.
- Success: lower alert fatigue, reduced manual toil, zero unauthorized action events.

### Phase 4: Selective approval-driven operations
- Add Quarantine Recommendation Agent and Update Rollout Risk Agent tightly tied to approval workflow.
- Success: reduced incident blast radius, faster safe containment, stable false-positive rates.

## 13) Concrete Workflow Examples
### A) Command preflight risk advisory
1. Operator initiates sensitive action via mobile.
2. Control-plane receives intent at `/api/commands` and gathers context from policy, device state, and recent telemetry.
3. Command Risk Advisor produces recommendation envelope with risk score and required approvals.
4. Operator approves/rejects; only approved requests continue through deterministic `PolicyEvaluator`.
5. If approved and allowed by policy, command is signed and dispatched via gateway `/api/v1/command/dispatch`.

### B) Telemetry anomaly triage
1. Gateway ingests telemetry and forwards summary webhooks upstream.
2. Telemetry Anomaly Triage Agent correlates telemetry spikes with command outcomes and attestation updates.
3. Agent emits ranked triage recommendations with context references (`command_id`, telemetry window, attestation event).
4. SOC sees prioritized queue; deterministic alert state changes remain in control-plane APIs.

### C) Quarantine recommendation flow
1. Attestation mismatch + repeated high-risk failures trigger correlation pipeline.
2. Quarantine Recommendation Agent emits `recommend_quarantine` with confidence and evidence.
3. Human approver validates recommendation and executes deterministic quarantine action through gateway admin endpoint.
4. Audit trail records recommendation, approver identity, execution event, and post-action verification status.

### D) Incident reconstruction and forensics
1. Investigator requests incident reconstruction for a device/time window.
2. Incident Timeline Builder merges command lifecycle, ack/result, online/offline transitions, and audit chain references.
3. Audit Chain Forensics Assistant highlights integrity anomalies and unresolved causality gaps.
4. Output is stored as investigation artifact; no mutation of source audit records is allowed.

## 14) First Moves (Recommended)
- **First agent**: Command Risk Advisor.
- **First augmented workflow**: command preflight + SOC triage before sensitive dispatch.
- **First data pipeline**: normalized command/telemetry/audit timeline index with strong IDs and lineage.
- **First guardrail**: deny-by-default action gateway with mandatory approval token for any disruptive execution path.

## 15) Operational Reality Check
This strategy deliberately avoids "agents everywhere." It places AI where Quoodle gains leverage (triage, correlation, explanation, workflow acceleration) and keeps deterministic enforcement where Quoodle earns trust (identity, cryptography, policy, replay safety, and privileged execution). That balance is the only viable path for an AI-enabled zero-trust control system.
