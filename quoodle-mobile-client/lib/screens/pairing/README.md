# QR Scanner Setup

This document describes how to set up camera permissions for the QR code scanner feature.

## Platform Configuration

### Android

Add camera permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Camera permission for QR scanning -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />

    <application
        ...
    </application>
</manifest>
```

### iOS

Add camera usage description to `ios/Runner/Info.plist`:

```xml
<dict>
    ...
    <key>NSCameraUsageDescription</key>
    <string>Camera access is required to scan device pairing QR codes.</string>
    ...
</dict>
```

## QR Code Format

The app expects QR codes in the following JSON format:

```json
{
  "type": "quoodle_pair",
  "version": 1,
  "device_id": "PC-001-ABCD",
  "pair_token": "abc123def456...",
  "pair_session_id": "sess_xyz789...",
  "timestamp": "2026-01-13T12:00:00Z",
  "controller_url": "https://api.example.com",
  "device_label": "Office PC"
}
```

### Required Fields

| Field             | Type   | Description                            |
| ----------------- | ------ | -------------------------------------- |
| `type`            | string | Must be `"quoodle_pair"`               |
| `version`         | int    | Schema version (currently `1`)         |
| `device_id`       | string | Unique device identifier               |
| `pair_token`      | string | One-time pairing token                 |
| `pair_session_id` | string | Pairing session identifier             |
| `timestamp`       | string | ISO 8601 UTC timestamp (max 5 min old) |

### Optional Fields

| Field            | Type   | Description                     |
| ---------------- | ------ | ------------------------------- |
| `controller_url` | string | API base URL (for multi-tenant) |
| `device_label`   | string | Human-readable device name      |

## Features

- **Camera scanning**: Real-time QR code detection with `mobile_scanner`
- **Manual entry**: Fallback text input for tokens
- **Permission handling**: Graceful degradation when camera denied
- **Flashlight toggle**: For low-light environments
- **Camera switch**: Front/back camera selection
- **Confirmation dialog**: User confirms device before pairing
- **Expiry validation**: QR codes expire after 5 minutes

## Generating Test QR Codes

Use the QR code generator at the control plane:

```bash
# Via API
curl -X POST https://api.example.com/pair/init \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"device_label": "Test Device"}'
```

Or generate manually for testing:

```python
import json
import qrcode
from datetime import datetime, timezone

data = {
    "type": "quoodle_pair",
    "version": 1,
    "device_id": "TEST-001",
    "pair_token": "test-token-123",
    "pair_session_id": "sess-test-456",
    "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
}

qr = qrcode.make(json.dumps(data))
qr.save("test_pairing_qr.png")
```
