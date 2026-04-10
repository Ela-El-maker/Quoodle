# quoodle-mobile-client

Operator mobile application for Quoodle device fleet operations.

This app is used to:

- authenticate operators
- monitor fleet health
- inspect device details and alerts
- pair devices via QR/manual token
- issue privileged/sensitive commands with 2FA flow
- review command timelines, notifications, scheduler, analytics, and audit views

## Stack

- Flutter (Material 3)
- Dart
- Riverpod (state orchestration)
- GoRouter (routing/redirects)
- Dio (API client abstraction)
- Shared Preferences + Secure Storage (local/session persistence)
- Sizer (responsive helpers)

## Runtime Architecture

Dependency direction:

`presentation -> application/state -> domain <- data`

Key rules:

- presentation does not directly call data sources
- repositories implement domain contracts
- app layer owns bootstrap, routing, and dependency composition
- core layer owns cross-cutting concerns (errors/network/storage/services)

Reference architecture notes:

- `docs/mobile-architecture.md`
- `docs/mobile-feature-template.md`

## Design System (Current App Design)

Source: `lib/theme/app_theme.dart`

- Visual mode: dark command-center UI with glass surfaces
- Primary color: `#00D4FF`
- Secondary color: `#10B981`
- Warning/Error: `#F59E0B` / `#EF4444`
- Base surfaces:
  - background `#0B0D10`
  - surface `#12161B`
  - surfaceVariant `#181D23`
  - border `#252B33`
- Typography:
  - IBM Plex Sans (UI text)
  - IBM Plex Mono (technical metadata/code-like labels)
- Navigation language:
  - liquid/glass bottom nav on phone
  - nav rail on tablet

## App Bootstrap

Bootstrap entry:

- `lib/main.dart`
- `lib/app/bootstrap/bootstrap.dart`

Startup behavior:

- initializes Flutter bindings
- configures global error widget
- locks orientation to portrait
- initializes notification service post-first-frame

## Routing and Navigation

Router source:

- `lib/app/router/app_router.dart`

Route constants:

- `lib/app/router/route_paths.dart`
- `lib/app/router/route_names.dart`

Navigation helper:

- `lib/app/router/app_navigator.dart`

Auth redirect guard:

- `lib/app/router/route_guards.dart`

### Full Page Catalog (All Routes)

| Route Path                    | Screen                   | Purpose                                      |
| ----------------------------- | ------------------------ | -------------------------------------------- |
| `/`                           | AuthenticationScreen     | Initial route, auth gate entry               |
| `/authentication-screen`      | AuthenticationScreen     | Login / 2FA authentication                   |
| `/dashboard-screen`           | DashboardScreen          | Fleet overview, KPIs, chart, activity        |
| `/devices-screen`             | DevicesScreen            | Device inventory and quick actions           |
| `/device-detail-screen`       | DeviceDetailScreen       | Deep device inspection and actions           |
| `/command-timeline-screen`    | CommandTimelineScreen    | Command execution timeline and results       |
| `/alerts-screen`              | AlertsScreen             | Fleet alert triage and drill-in              |
| `/qr-scanner-screen`          | QrScannerScreen          | Device pairing via QR/manual token           |
| `/send-command-screen`        | SendCommandScreen        | Command authoring + policy + 2FA submit      |
| `/settings-screen`            | SettingsScreen           | Profile/account + notification/user settings |
| `/scheduler-screen`           | SchedulerScreen          | Job scheduling and execution history         |
| `/notification-center-screen` | NotificationCenterScreen | Notification inbox and read/delete ops       |
| `/audit-log-screen`           | AuditLogScreen           | Audit event stream                           |
| `/analytics-screen`           | AnalyticsScreen          | Analytics dashboards and breakdowns          |

### Nested Page Sections and Tabs

- Bottom navigation primary tabs:
  - Fleet
  - Devices
  - Commands
  - Alerts
  - Profile

- Device detail tabs:
  - Overview
  - Telemetry
  - Commands
  - Alerts
  - Audit

- Scheduler tabs:
  - Active
  - Paused
  - History

- Analytics tabs:
  - Commands
  - Health
  - Compliance
  - Operators

- Settings tabs:
  - Account
  - Notifications
  - Command Queue

## Command Catalog (Send Command Screen)

Source: `lib/presentation/send_command_screen/send_command_screen.dart`

Implemented command methods:

| Method ID            | Label        | Sensitive |
| -------------------- | ------------ | --------- |
| `screenshot_capture` | Screenshot   | Yes       |
| `process_list`       | Process List | No        |
| `running_apps`       | Running Apps | No        |
| `filesystem`         | Filesystem   | Yes       |
| `system_info`        | System Info  | No        |
| `network_info`       | Network Info | No        |
| `collect_telemetry`  | Telemetry    | No        |
| `lock_screen`        | Lock Screen  | No        |
| `policy_sync`        | Policy Sync  | No        |
| `upload_file`        | Upload File  | Yes       |
| `create_file`        | Create File  | Yes       |
| `reboot`             | Reboot       | Yes       |

Command flow:

- operator chooses method
- method-specific params form is rendered
- sensitive methods require explicit confirm path
- operator passes OTP verification
- app navigates to command timeline with payload/context

## API Endpoint Catalog

This section includes both:

- app-configured endpoints in mobile code
- system protocol endpoints documented for control-plane/gateway integration

### A) Mobile App Configured Endpoints (Current)

Source: `lib/core/network/endpoints.dart`

| Endpoint             | Purpose                               |
| -------------------- | ------------------------------------- |
| `/auth/login`        | operator login                        |
| `/auth/refresh`      | refresh access token/session          |
| `/auth/me`           | get operator profile/session identity |
| `/dashboard/summary` | retrieve dashboard summary payload    |

Notes:

- API client abstraction lives in `lib/core/network/api_client.dart` and `lib/core/network/dio_provider.dart`.
- These endpoints are the canonical constants currently defined in mobile code.

### B) Quoodle System Protocol Endpoints (Control Plane + Gateway)

Source: `../docs/protocols/api_endpoints.md`

#### Laravel <-> Mobile (REST)

Functional surface documented in protocol:

- register
- login
- 2fa/verify
- token/refresh
- logout
- devices list/detail/rename
- pairing init/confirm
- commands CRUD
- telemetry latest/history
- updates listing
- alerts list/ack
- audit trail

#### Laravel -> FastAPI (REST/Webhook)

- `POST /api/v1/command/dispatch`
- `POST /api/v1/policy/push`
- `POST /api/v1/update/deploy`
- `POST /api/v1/webhook/device/paired`

#### FastAPI -> Laravel (REST/Webhook)

- `POST /api/v1/webhook/device/online`
- `POST /api/v1/webhook/device/offline`
- `POST /api/v1/webhook/device/activated`
- `POST /api/v1/webhook/command/result`
- `POST /api/v1/webhook/command/ack`
- `POST /api/v1/webhook/telemetry/summary`
- `POST /api/v1/webhook/security/attestation`

## Project Structure (Current)

```text
quoodle-mobile-client/
├── lib/
│   ├── app/                  # bootstrap, DI, router, app composition
│   ├── core/                 # cross-cutting infra (errors/network/storage/services)
│   ├── features/             # feature modules (presentation/domain/data)
│   ├── models/               # shared model classes
│   ├── presentation/         # screen implementations
│   ├── services/             # legacy/compat service facades
│   ├── theme/                # visual system and theme tokens
│   └── widgets/              # reusable UI widgets
├── docs/                     # mobile architecture docs
├── test/                     # unit/widget/feature tests
└── pubspec.yaml
```

## State Management

- Riverpod controllers are primary orchestration surface
- `ConsumerStatefulWidget` is used for local view state + provider integration
- local ephemeral state remains via `setState` where appropriate (input/UI toggles)

## Performance and UX Notes

- startup heavy initialization shifted away from first frame where possible
- non-critical dashboard sections use deferred loading (`DeferredLoader`)
- overflow protections applied to short-screen scenarios (notably QR manual entry)
- command timeline includes bottom navigation and safe back behavior

## Security Notes

- sensitive command methods require policy/confirmation + OTP flow
- secure storage abstractions are present for token/session data handling
- no local command execution; actions are dispatched as intent/operations flow

## Build and Run

Prerequisites:

- Flutter SDK (stable channel)
- Android Studio/Xcode toolchain

Install and run:

```bash
flutter pub get
flutter run
```

Analyze and test:

```bash
flutter analyze lib
flutter test
```

## Maintainer Notes

If routes, command methods, or endpoint constants change, update this README in the same PR so docs remain source-aligned.
