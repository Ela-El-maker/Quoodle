# 📱 quoodle-mobile-client

**Role**: Client / Intent
**Tech Stack**: Flutter (Dart)
**Responsibility**: User Interface, Pairing, Command Issuance, Telemetry View.

---

## 📖 Overview

The `quoodle-mobile-client` is the operator's interface to the Quoodle system. It allows administrators to:

1.  **Pair**: Scan QR codes displayed by new Agents to claim ownership.
2.  **Control**: Issue signed commands (e.g., "Lock Screen", "Reboot") to devices.
3.  **Monitor**: View real-time telemetry and alerts via WebSocket/FCM.

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
