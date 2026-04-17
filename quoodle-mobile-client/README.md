# quoodle-mobile-client

Flutter mobile operator app for Quoodle.

Primary use cases:

- authentication and session management
- device pairing (QR or token-assisted)
- fleet/device visibility
- command issue and result tracking
- alerts, notifications, scheduling, and audit views

## 1. Stack

- Flutter
- Dart
- Riverpod
- GoRouter
- Dio
- Shared preferences + secure storage

## 2. Architecture

Layer direction:

`presentation -> application/state -> domain <- data`

Principles:

- UI layer does not directly own data source logic
- repositories implement domain contracts
- app bootstrap composes dependencies and navigation guards
- core layer owns networking, storage, and shared services

## 3. Startup and Routing

Entry points:

- `lib/main.dart`
- `lib/app/bootstrap/bootstrap.dart`

Router:

- `lib/app/router/app_router.dart`

Common route surfaces include authentication, dashboard, devices, command timeline, scanner, alerts, settings, scheduler, notifications, and audit views.

## 4. Command UX Scope

Mobile command flow supports command selection, parameter shaping, sensitive confirmation, OTP verification path (where enabled), and timeline/result inspection.

## 5. Networking

Endpoint constants live in:

- `lib/core/network/endpoints.dart`

Primary auth/session APIs:

- `/auth/login`
- `/auth/refresh`
- `/auth/me`

Additional device/pair/command APIs are consumed through feature repositories and service adapters.

## 6. Build and Run

```powershell
flutter clean
flutter pub get
flutter run
```

## 7. Analyze and Test

```powershell
flutter analyze lib
flutter test
```

## 8. Local Integration Notes

- when testing against local backend from physical phone, use host LAN IP, not `localhost`
- ensure control plane/gateway are reachable from phone network
- verify token refresh and auth redirects before pairing tests

## 9. Troubleshooting

- scanner not detecting QR: verify camera permission and QR payload format
- auth loops: inspect refresh interceptor and `/auth/me` response
- missing devices: verify pairing completed and role assignment updated
- command submit fails: verify endpoint base URL and session token freshness
