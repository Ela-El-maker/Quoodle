# quoodle-mobile-client

Operator mobile app for the Quoodle system. Pair devices, issue signed commands, view real-time telemetry, and review audit logs.

**Stack:** Flutter / Dart

## Build & Run

**Prerequisites:** Flutter SDK (stable), Android Studio or Xcode

```bash
flutter pub get
flutter run
```

## Features

- **Pairing** — scan QR codes to claim new devices
- **Commands** — issue signed commands (lock screen, reboot, etc.)
- **Telemetry** — real-time device health and metrics
- **Audit** — browse tamper-evident command and action history
- **Compliance** — device compliance state and alerts

## Project Structure

```
lib/
├── models/          # Data models (device, command, telemetry)
├── screens/         # UI screens (auth, fleet, device detail, pairing)
├── services/        # API and auth services
├── providers/       # State management
├── theme/           # App theme and styling
├── utils/           # Crypto, RBAC, signatures
└── widgets/         # Reusable UI components
assets/              # Images and icons
test/                # Widget and unit tests
```

## Security

- Generates a user keypair on login — signs all command intents on-device
- JWT-based session with the Control Plane
- Never stores raw private keys from other components
- Never executes commands locally — only creates signed intent
