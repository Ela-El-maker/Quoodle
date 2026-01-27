# 📱 quoodle-mobile-client

**Role**: Client / Intent
**Tech Stack**: Flutter (Dart)

**Responsibility**: User Interface, Pairing, Command Issuance, Telemetry View, Audit Log Access, Compliance Monitoring.

---

## 📖 Overview

The `quoodle-mobile-client` is the operator's interface to the Quoodle system. It allows administrators to:

1.  **Pair**: Scan QR codes displayed by new Agents to claim ownership.
2.  **Control**: Issue signed commands (e.g., "Lock Screen", "Reboot") to devices.
3.  **Monitor**: View real-time telemetry, compliance state, and alerts via WebSocket/FCM.
4.  **Audit**: Review audit logs and command history for all managed devices.

Mobile App Architecture (Operator App)
What the app is responsible for

Authenticate operator (JWT + MFA)

Show device fleet + compliance state

Create command intents (never executes anything locally)

Show command timeline, results, artifacts

Receive push notifications for critical events

What it must NEVER do

Store raw private keys (control plane keys, device keys)

“Run commands” locally

Accept unsigned or tampered command/result objects

High-Level System Diagram

┌─────────────────────────────────────────────────────────────────────────────┐
│ MOBILE APP │
│ (iOS / Android: Flutter / RN / Native) │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ 1) PRESENTATION LAYER (UI) │
│ - Screens: Login/MFA, Fleet, Device Detail, Command Composer, Results │
│ Artifacts Viewer, Compliance, Audit, Settings │
│ - Navigation: stacks/tabs, deep-links (device/:id, command/:id) │
│ - UI State: ViewModels/Bloc/Redux (per-screen + global session store) │
│ - Form Renderer: dynamic command params UI from method schema │
└───────────────▲─────────────────────────────────────────────────────────┘
│ user intent/events (tap, submit, filter, deep-link)
│ state updates, validation errors, loading states
┌───────────────┴─────────────────────────────────────────────────────────┐
│ 2) DOMAIN LAYER (USE-CASES / BUSINESS RULES) │
│ Auth: login, MFA step-up, refresh, logout │
│ Devices: list, detail, tags, quarantine view │
│ Commands: create intent, approve step-up, track lifecycle, cancel │
│ Artifacts: fetch meta, download, verify checksum │
│ Compliance: show decision + remediation │
│ Audit: feed, filters, export request │
└───────────────▲─────────────────────────────────────────────────────────┘
│ repositories (interfaces)
│ pure models (Device, Command, Artifact, PolicyDecision)
┌───────────────┴─────────────────────────────────────────────────────────┐
│ 3) DATA LAYER (REPOSITORIES + API + CACHE) │
│ - REST API client (Control Plane endpoints) │
│ - DTO ↔ Domain mapping │
│ - Local DB cache (SQLite/Room/CoreData) │
│ - Sync engine (delta sync, conflict rules, pagination cursors) │
│ - Artifact download manager (resume, retry, checksum verify) │
└───────────────▲─────────────────────────────────────────────────────────┘
│ HTTPS (JWT), retries/backoff
│ push-triggered refreshes
┌───────────────┴─────────────────────────────────────────────────────────┐
│ 4) SECURITY & TRUST LAYER │
│ - Secure storage (Keychain/Keystore): tokens, install-id, push token │
│ - Token lifecycle: access/refresh rotation, expiry handling │
│ - Step-up MFA gate for sensitive commands │
│ - Optional hardening: jailbreak/root signals, cert pinning, redaction │
│ - Artifact integrity: checksum verification + trust badge │
└───────────────▲─────────────────────────────────────────────────────────┘
│
│ notifications / background wakeups
┌───────────────┴─────────────────────────────────────────────────────────┐
│ 5) BACKGROUND & EVENTS LAYER │
│ - Push handler (APNs/FCM): command_completed, compliance_failed, etc. │
│ - Background fetch (WorkManager / BGTasks): sync devices/commands │
│ - Local notifications: summaries, alerts │
│ - Telemetry: crash reports + app metrics (with redaction) │
└───────────────▲─────────────────────────────────────────────────────────┘
│
│ network + platform
┌───────────────┴─────────────────────────────────────────────────────────┐
│ 6) PLATFORM/INFRASTRUCTURE │
│ - Networking stack: timeouts, retries, offline detection │
│ - Storage: DB, file sandbox (artifact storage) │
│ - Feature flags + remote config │
│ - Logging: structured + redacted │
└─────────────────────────────────────────────────────────────────────────┘

EXTERNAL “INS/OUTS” (what the mobile app talks to)

┌──────────────────────────────┐ ┌─────────────────────────────────────┐
│ Push Provider (APNs/FCM) │───────▶│ Background/Push Handler │
└──────────────────────────────┘ └─────────────────────────────────────┘

┌──────────────────────────────┐ ┌─────────────────────────────────────┐
│ CONTROL PLANE (Laravel) │◀──────▶│ REST API Client (JWT) │
│ - auth, policy, audit │ │ - login/MFA/commands/devices/audit │
└──────────────────────────────┘ └─────────────────────────────────────┘

(Optional)
┌──────────────────────────────┐ ┌─────────────────────────────────────┐
│ Artifact Storage (S3/minio) │◀──────▶│ Download Manager + Integrity Verify │
└──────────────────────────────┘ └─────────────────────────────────────┘

Mobile App
├─ UI / Presentation
│ ├─ Screens (Auth, Fleet, Device, Command, Audit, Settings)
│ ├─ Components (Cards, Lists, Filters, Editors)
│ ├─ Navigation + Deep Links
│ ├─ State mgmt (ViewModels / Redux / Bloc)
│ └─ UI security (biometric gate, screenshot prevention optional)
│
├─ Domain (Business Use-Cases)
│ ├─ Auth use-cases (login, MFA, refresh, logout)
│ ├─ Device use-cases (list, detail, tags, quarantine)
│ ├─ Command use-cases (create, approve step-up, poll, cancel)
│ ├─ Artifact use-cases (fetch metadata, download, verify checksum)
│ ├─ Policy/Compliance use-cases (display, remediation)
│ └─ Audit use-cases (feed, filters, export request)
│
├─ Data Layer
│ ├─ API clients (REST)
│ ├─ DTO mapping (API ↔ domain models)
│ ├─ Offline cache (DB)
│ ├─ Sync engine (delta sync + conflict rules)
│ └─ Telemetry client (crash + app metrics)
│
├─ Security Layer
│ ├─ Secure storage (Keychain/Keystore)
│ ├─ Token lifecycle (access/refresh, rotation)
│ ├─ Device binding (installation id, attested device info)
│ ├─ Crypto utilities (hashing, checksum verify)
│ └─ Hardening (root/jailbreak detection, cert pinning optional)
│
├─ Background Services
│ ├─ Push notifications handler (FCM/APNs)
│ ├─ Background fetch / sync (WorkManager / BGTasks)
│ ├─ Upload/download manager (artifacts)
│ └─ Local notification scheduler
│
└─ Platform / Infrastructure
├─ Networking (HTTP stack, retries, timeouts)
├─ Database (SQLite/Room/CoreData)
├─ Logging (redaction)
├─ Feature flags
└─ Config (env, endpoints)

1. Presentation Layer (UI): What’s Inside
   Screens (canonical)

Auth

Login (email/password)

MFA (TOTP / push approve / recovery)

Session issues (re-auth, device changed)

Fleet

Device list (filters: online, quarantined, compliant, OS)

Device detail

Command Center

Command composer (method picker + parameter forms)

Command history (search, filter by device/method/result)

Command detail (timeline + envelopes + audit evidence)

Artifacts

Screenshot viewer

File browser / downloads

Artifact integrity page (checksum verified/unverified)

Compliance

Device compliance view: state, failed rules, remediation steps

Audit

Audit feed (immutable events)

Export audit request (async)

Settings

Profile, roles, org, logout

Notification preferences

“Training mode” switch (if you add it)

UI Components (reusable)

DeviceCard, CommandCard, ComplianceBadge

FilterChips, SearchBar, MethodPicker

ParamEditor components:

string, int, bool, enum, path, list

validation hints + bounds

Navigation + Deep links

quoodle://device/<device_id>

quoodle://command/<command_id>

Push notification opens exact command/device page.

State management patterns

Per-screen store (VM/Bloc) + global session store

UI supports:

optimistic updates (show queued command immediately)

eventual reconciliation when server returns final state

2. Domain Layer: Use-Cases and Rules (Everything)
   Auth

Login(email, password, device_fingerprint)

StartMFA(challenge_type)

CompleteMFA(code|push)

RefreshSession()

Logout()

RequireStepUp(reason) (for sensitive commands)

Devices

GetDevices(filters, pagination)

GetDevice(device_id)

GetDeviceSessions(device_id) (optional)

QuarantineDevice(device_id, reason) (admin/operator role)

RotateDeviceKey(device_id) (admin only)

TagDevice(device_id, tags) (optional)

Commands

CreateCommand(device_id, method, params, sensitive)

ApproveCommandWithMFA(command_id) (if server requires)

GetCommand(command_id)

WatchCommand(command_id) (polling/SSE)

CancelCommand(command_id) (if supported)

ReplaySafetyCheck(client_message_id) (client-side only for UX)

Artifacts

ListArtifacts(device_id | command_id)

GetArtifactMeta(artifact_id)

DownloadArtifact(artifact_id)

VerifyArtifactChecksum(artifact_id, checksum)

Compliance & Policy UX

GetCompliance(device_id)

ExplainPolicyDecision(command_id) (display reason)

ShowRemediationSteps(failed_rules[])

Audit

GetAuditFeed(filters, range)

RequestAuditExport(filters, range)

DownloadAuditExport(export_id)

3. Data Layer: API + Models + Cache + Sync
   API Clients (REST)

AuthAPI

POST /api/login

POST /api/mfa/\*

POST /api/refresh (if exists)

DevicesAPI

GET /api/devices

GET /api/devices/{id}

CommandsAPI

POST /api/commands

GET /api/commands/{id}

GET /api/devices/{id}/commands (optional)

ArtifactsAPI

GET /api/artifacts/...

AuditAPI

GET /api/audit

POST /api/audit/export

Domain Models (examples)

UserSession { access_token, refresh_token?, expires_at, roles[], org_id }

Device { id, name, os, version, online, quarantine, compliance }

Command { id, device_id, method, params, state, policy, compliance, created_at }

Artifact { id, type, size, checksum, expires_at, url? }

Cache / Local DB Tables

devices

device_status_snapshots

commands

command_events (timeline)

artifacts

audit_events (optional cached)

sync_state (last cursor / etag)

Sync Engine

Background pull:

fetch devices delta

fetch command updates

Conflict rules:

server is source of truth

client only stores presentation state (filters, UI prefs)

4. Security Layer: What’s Inside
   Secure Storage

Access/refresh tokens

Installation ID / device binding ID

Notification token (FCM/APNs)

Cached role/org id (not secret but integrity-sensitive)

Token lifecycle

Access token short TTL

Refresh token rotation (if used)

Auto-logout on:

repeated refresh failures

role removed

token replay detected (server side)

Device binding (recommended)

Installation ID: random UUID stored in secure storage

Send it on login as device_fingerprint

Server can detect “same operator logged in from new phone”

App hardening options

Root/jailbreak detection (warn or lock sensitive actions)

TLS cert pinning (optional for production)

Redacted logging (never log JWT, never log artifact URL)

Artifact integrity

Verify checksum after download

Show “verified/unverified” badge in UI

5. Background & Notifications: What’s Inside
   Push handler

Notification types:

command_completed

device_offline

compliance_failed

quarantine_changed

On receive:

update local cache

show local notification (if app background)

deep link into relevant screen

Background jobs

periodic sync (every N minutes)

retry logic with jitter/backoff

artifact downloads managed separately:

pause/resume

cellular-only option

integrity verify post-download

6. “Ins & Outs” (Concrete Inputs/Outputs)
   Inputs (to the app)

User taps / searches / composes commands

Backend responses (JWT, devices list, command state changes)

Push notifications payloads

Deep links

Network state changes (offline/online)

Outputs (from the app)

Auth requests

Commands created (intent only)

Polling requests for updates

Artifact download requests

Admin actions (quarantine/rotate)

7. Method Schema System (So UI isn’t hardcoded)

To avoid rewriting screens per command, the app should consume a method schema from the control plane:

Example schema:

method name: screenshot

params:

display: enum [primary, all]

quality: int 1..100

include_cursor: bool

sensitivity: true/false

requires_step_up: true/false

role requirements: [operator, admin]

The app uses this to:

render parameter forms

validate client-side

show warnings (“Sensitive action: MFA required”)

## 🛠️ Build & Run

### Prerequisites

- Flutter SDK (stable)
- Android Studio / Xcode

### Setup

```bash
flutter pub get
```

### Running

```bash
flutter run
```

## 🔐 Security Context

- **User Keys**: Generates a user-specific keypair on login.
- **Command Signing**: Signs all command intents on-device before sending them to the Control Plane.
- **Authentication**: JWT-based session with `quoodle-control-plane`.
