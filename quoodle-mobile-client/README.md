# quoodle-mobile-client

Flutter mobile operator app for Quoodle.

This client brings pairing, fleet awareness, command workflows, and operational visibility into a mobile-first experience.

## 1. Architecture

### 1.1 Layering Model

`presentation -> application/state -> domain <- data`

- Presentation: Flutter widgets and route screens.
- Application/State: Riverpod providers and state orchestration.
- Domain: entities/use cases/contracts.
- Data: repository implementations, network/storage adapters.

### 1.2 Why This Model

- testability through clear boundaries
- predictable feature growth
- lower coupling between UI and transport details

## 2. Stack and Why

- Flutter for shared Android/iOS codebase.
- Riverpod for explicit dependency/state wiring.
- GoRouter for declarative route control.
- Dio for interceptors, retries, and auth token middleware.
- secure storage + shared preferences for token/session persistence.

## 3. Startup and Session Strategy

Boot path:

- initialize env and dependencies
- hydrate session/token state
- run auth guard checks
- route to authenticated or unauthenticated surfaces

Token refresh behavior is handled through network interceptors to reduce manual re-auth churn.

## 4. Pairing Strategy

Supported pairing patterns:

- token-based claim flow
- QR scanning flow

Design requirements:

- scanner payload validation
- explicit pending/confirm/complete states
- role and ownership update after successful claim

## 5. Command UX Strategy

Command workflow includes:

- device selection
- command method selection
- parameter composition
- sensitive-action confirmation (where required)
- submission and timeline observation
- result retrieval and error-state explanation

## 6. Networking and Protocol Usage

Endpoint contracts are centralized under:

- `lib/core/network/endpoints.dart`

Key API groups:

- auth/session (`/auth/login`, `/auth/refresh`, `/auth/me`)
- pairing
- device list/detail
- command submit/result
- telemetry and alerts

## 7. Build and Run

```powershell
flutter clean
flutter pub get
flutter run
```

## 8. Analyze and Test

```powershell
flutter analyze lib
flutter test
```

## 9. Local Integration Notes

- Use host LAN IP when testing on physical devices.
- Do not use `localhost` on phone builds for backend access.
- Verify both control-plane and gateway reachability from phone network.

## 10. Troubleshooting

### QR Scan Not Detecting

- confirm camera permissions
- verify QR payload format and content
- verify environment base URLs in app bootstrap

### Sign-In Loop

- inspect refresh interceptor behavior
- inspect `/auth/me` failures and token storage state

### Missing Devices

- confirm pairing and ownership completion
- verify role permissions and endpoint access

### Command Submit Fails

- confirm token freshness
- verify endpoint base URL points to reachable backend

## 11. Sequence Diagrams

### 11.1 Mobile Sign-In and Refresh

```text
Mobile App           API Gateway/Control Plane        Token Storage
    |                           |                         |
    | login creds               |                         |
    |-------------------------->| issue jwt+refresh       |
    |<--------------------------|                         |
    | store tokens              |------------------------>|
    | request protected API     |                         |
    |-------------------------->| 401? refresh            |
    | refresh token             |                         |
    |-------------------------->| new access token        |
```

### 11.2 Mobile QR Pair Flow

```text
Mobile Scanner      Control Plane        Gateway          Agent Runtime
      |                  |                 |                  |
      | scan QR payload  |                 |                  |
      |----------------->| pair request    |                  |
      |                  |---------------> | pair session     |
      |                  |<--------------- | detected         |
      | confirm ownership|                 |                  |
      |----------------->| link device     |                  |
```
