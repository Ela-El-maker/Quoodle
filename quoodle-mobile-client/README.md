# quoodle-mobile-client

Flutter mobile client for the Quoodle secure device control platform.

This repository contains the Flutter application used as the mobile operator
client: pairing with devices via QR, issuing commands, viewing telemetry and
alerts, and receiving real-time updates.

## Quick Links

- Project root: `quoodle` monorepo
- Mobile app folder: `quoodle-mobile-client`

## Features

- Device pairing (QR-based)
- Real-time telemetry via WebSocket
- Push notifications (FCM)
- Offline caching and stale-while-revalidate support
- Command sending and command history

## Prerequisites

- Flutter SDK (stable) — see https://docs.flutter.dev/get-started/install
- Android Studio / Xcode (for emulators and platform tooling)
- A connected device or emulator
- Optional: Firebase project for push notifications

## Environment & Configuration

This app reads runtime endpoints and keys from a small config file or
environment variables injected at build/run time. Common values you may need:

- `API_BASE_URL` — backend API (Laravel / FastAPI) base URL
- `FCM_SENDER_ID` / `google-services.json` / `GoogleService-Info.plist` — for FCM

Place platform config files in the usual Flutter locations (`android/` and
`ios/`) or provide values via CI variables for builds.

## Setup (Development)

1. Install Flutter and ensure `flutter` is on your PATH.
2. From this directory, fetch dependencies:

```bash
cd quoodle-mobile-client
flutter pub get
```

3. (Optional) If you use Firebase, add the platform config files:

- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`

## Run (Development)

Run on the default connected device/emulator:

```bash
flutter run
```

Run on a specific device or emulator (Android example):

```bash
flutter emulators --launch <emulator_id>
flutter run -d emulator-5554
```

## Build (Release)

Android APK:

```bash
flutter build apk --release
```

iOS (Xcode):

```bash
flutter build ios --release
# then open ios/Runner.xcworkspace in Xcode to archive/sign
```

## Testing & Static Analysis

Run unit & widget tests:

```bash
flutter test
```

Run static analysis:

```bash
flutter analyze
```

## Project Structure (high level)

- `lib/` — application source
  - `main.dart` — app entry
  - `models/` — data models (Device, Alert, Telemetry, Command)
  - `services/` — API, WebSocket, cache, push integrations
  - `screens/` / `widgets/` — UI
- `test/` — unit and widget tests
- `android/`, `ios/` — platform projects

Refer to in-repo docs in `docs/` for cross-repo architecture and protocols.

## Development Notes

- Use `CacheService` for local caching and the offline repository API in
  `OfflineRepository` for unified data access.
- Keep model `toJson()` and `fromJson()` implementations in sync with the
  backend API contracts.
- Use `flutter pub upgrade` periodically to keep dependencies current.

## Troubleshooting

- If the app can't reach the backend ensure `API_BASE_URL` is correct and the
  device/emulator has network access.
- For FCM issues, verify the Firebase configuration files are correct and
  package IDs match those in the Firebase console.

## Contributing

1. Open an issue describing the change.
2. Create a small, focused branch: `feature/<short-desc>` or `fix/<short-desc>`.
3. Add tests for new behavior when applicable.
4. Submit a pull request referencing the issue.

## License

This project inherits the monorepo license. See the top-level `LICENSE` file
for details.

---

If you want, I can also add a short development checklist or CI snippets for
building the mobile client in your pipeline. Would you like that?
