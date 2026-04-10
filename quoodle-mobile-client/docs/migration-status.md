# Migration Status

## Completed

- Added architecture skeleton: `app`, `core`, `features`, `shared`.
- Added baseline core primitives:
  - `core/errors` (`Failure`, `Result`, mapper)
  - `core/network` (API client + Dio shell + interceptors)
  - `core/storage` abstractions
  - service abstractions (logger/analytics/crash reporting)
- Added bootstrap layer and new `QuoodleApp` entry wiring.
- Added routing foundation with compatibility route map + GoRouter definitions.
- Added centralized typed navigation coordinator in `app/router/app_navigator.dart`.
- Removed duplicated bottom-nav route arrays from screens/widgets and routed them through the shared navigator.
- Migrated auth flow to feature module with Riverpod controller + use cases.
- Migrated dashboard loading/refresh flow to feature module controller.
- Split push notification service into core location with compatibility export.
- Added architecture guard tests for migrated reference features (`auth`, `dashboard`).
- Added feature-owned Riverpod providers for notifications, scheduler, and offline command queue.
- Removed manual `addListener/removeListener` UI wiring in scheduler/notification/settings and app navigation badge.
- Moved scheduler and offline queue implementations under feature boundaries with compatibility exports:
  - `features/scheduler/data/services/scheduler_service.dart`
  - `features/commands/data/services/offline_command_queue.dart`
- Hardened queue initialization to prevent duplicate connectivity subscriptions.
- Migrated notifications into full feature module shape:
  - `features/notifications/domain` (entity, repository contract, use cases)
  - `features/notifications/data` (datasource, mapper, repository impl)
  - `features/notifications/presentation` (controller/state/providers)
- Rewired notification center screen to feature controller/state with UI parity.
- Added notification controller tests and extended architecture boundary checks to notifications.
- Migrated devices and device detail data/state flow to `features/devices` (repository + Riverpod controller/state).
- Migrated command timeline orchestration into `features/commands`:
  - domain/data/presentation layers for command result persistence + polling state machine
  - screen now renders provider state (timers/local DB removed from widget)
  - command timeline controller tests + architecture boundary checks extended to commands.
- Migrated send command orchestration to feature-owned controller state (`features/commands/presentation/providers/send_command_controller.dart`).
- Migrated alerts to full feature ownership:
  - `features/alerts/domain|data|presentation`
  - alert loading/filter/acknowledge flows owned by Riverpod controller.
- Migrated audit log filtering/search state to feature ownership:
  - `features/audit/domain|data|presentation`.
- Migrated analytics range selection to feature-owned state:
  - `features/analytics/presentation/providers`.
- Migrated settings notification/session state to feature-owned controller:
  - `features/settings/domain|presentation`.
- Added controller tests for alerts, audit, analytics, settings, and send command.
- Switched app runtime routing to `MaterialApp.router` + `GoRouter` source of truth.
- Wired centralized auth route guard redirects through router refresh state.
- Removed legacy named-route internals from active runtime flow.
- Updated `AppNavigator` to use `GoRouter` (`go`/`push`) while preserving compatibility method signatures.
- Preserved route-path constants via `AppRoutes` compatibility facade.
- Retired `core/app_export.dart` usage from app code and constrained it to a deprecated minimal export surface.
- Added hardening architecture tests for:
  - no global barrel imports (`core/app_export.dart`)
  - no named Navigator push APIs
  - no imports from legacy `lib/services/*` facade in app code.
- Removed internal imports of legacy service facades from bootstrap/tests.

## In Progress

- None.

## Pending

- Continue feature deepening where needed (for example, scheduler domain/repository split) without reintroducing legacy patterns.
