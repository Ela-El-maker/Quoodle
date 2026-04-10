# Quoodle Mobile Architecture

## Governing Rule

Dependency flow must be inward:

`presentation -> application/state -> domain <- data`

- Domain is Flutter-agnostic.
- Data implements domain repository contracts.
- Presentation never calls data sources directly.
- App layer owns bootstrap, router, and top-level composition.
- Core owns cross-cutting infrastructure only.

## Project Structure

- `lib/app`: bootstrap, routing, dependency composition.
- `lib/core`: errors, network, storage, cross-cutting services.
- `lib/features/<feature>`: feature modules with `presentation`, `domain`, and `data`.
- `lib/shared`: cross-feature pure types.

## Routing Policy

- `GoRouter` in `app/router/app_router.dart` is the runtime source of truth.
- Route constants are defined in `app/router/route_paths.dart` and mirrored by `AppRoutes` as a compatibility facade.
- Auth/session redirects are centralized in `app/router/route_guards.dart`.
- New navigation must use `AppNavigator` (`go`/`push`) and not named `Navigator.pushNamed*`.

## State Management Policy

- Riverpod is the standard for feature orchestration.
- Legacy `setState` remains only for local ephemeral widget state during migration.
- Async feature logic belongs in Riverpod controllers.

## Current Reference Features

- `features/auth`: session and authentication flow with use cases and repository contracts.
- `features/dashboard`: loading and refresh flow controlled by a feature controller.

## Non-Negotiables

- No direct API calls in screens.
- No feature business logic in `main.dart`.
- No new global singleton feature logic.
- All new data-backed screens must handle loading, error, and success states.
- No imports of legacy `lib/services/*` facades from app code.
- No usage of `core/app_export.dart` in new code.
