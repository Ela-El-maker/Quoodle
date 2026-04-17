# quoodle-control-plane-ui

Next.js control console for Quoodle operators and viewers.

This UI is a role-aware operational console that visualizes backend truth while providing controlled action entry points.

## 1. Frontend Architecture

### 1.1 Layering

- Route Layer: App Router route groups and page ownership.
- Data Layer: API handlers/services and client fetch adapters.
- Presentation Layer: reusable UI primitives and feature components.
- Policy Layer: role-based route and feature gating.

### 1.2 Rendering Strategy

- use server components for secure/session-aware composition where possible
- use client components for interactive dashboards, polling, and modals
- keep role-critical checks server-backed

## 2. Stack and Why

- Next.js 16 for route and rendering flexibility.
- React 19 for modern component model.
- TypeScript for contract safety.
- Tailwind for consistent design tokens and rapid component implementation.

## 3. UX Domains and Design Intent

- Viewer Console: discover and claim devices.
- Operator Console: execute commands and monitor outcomes.
- Device Management: status, compliance, inventory views.
- Command Trace: stage-by-stage lifecycle visibility.
- Results and History: output retrieval and audits.
- Telemetry and Alerts: operational health signals.

## 4. Role and Route Guarding

Role gating applies at navigation, page, and API access layers.

Expected principles:

- viewer has no command/alert action authority
- operator has command authority on owned devices
- admin has governance-level access

## 5. Data Freshness Strategy

Current pattern:

- adaptive polling for operational pages
- faster cadence when tab is visible
- slower cadence when hidden

Design goal:

- near-real-time operations without excessive backend pressure

## 6. Pairing UX Strategy

Pairing flow supports both token and QR pathways and should present these stages clearly:

- code generation/session wait
- device detected
- ownership confirm challenge
- role transition and redirect

The UI should avoid stale or optimistic completion states that are not backed by runtime evidence.

## 7. Build and Run

From `quoodle-control-plane-ui`:

```powershell
npm install
Copy-Item .env.local.example .env.local -Force
npm run dev
```

Build:

```powershell
npm run build
npm run start
```

## 8. Docker Mode

From repo root:

```powershell
docker compose up -d --build control-plane-ui
```

## 9. Troubleshooting

### Login Redirect Loop

- inspect `/api/auth/me` status and cookie lifecycle
- verify base URL env values for server/client calls

### Empty Device Views

- verify paired/owned devices in control-plane API
- verify role visibility and endpoint authorization

### Pair Modal Stalls

- inspect pair session endpoints
- validate gateway callbacks are arriving and reflected

### Build Errors (Encoding)

- ensure source files are UTF-8
- remove invalid byte sequences in edited files

## 10. Sequence Diagrams

### 10.1 Viewer Pair to Operator Transition

```text
Viewer Browser      UI App Router      API Route/Backend      Session Store
      |                  |                    |                    |
      | click Pair       |                    |                    |
      |----------------->| open modal         |                    |
      | enter token      | POST /pair/confirm |                    |
      |----------------->|------------------->| verify + elevate   |
      |                  |                    |--------update------>|
      |                  | refresh /auth/me   |                    |
      |                  |------------------->|                    |
      |                  | redirect /operator |                    |
      |<-----------------|                    |                    |
```

### 10.2 Adaptive Polling Behavior

```text
UI Tab State        Polling Loop        Devices API
    |                   |                  |
    | visible           | every 5s         |
    |------------------>|----------------->|
    | hidden            | every 30s        |
    |------------------>|----------------->|
```
