# Mobile App Integration Guide

How the Flutter app consumes backend APIs and notifications.

## Authentication
- User signs in via Laravel OAuth/JWT; tokens refreshed via `/auth/refresh`; store securely (Keychain/Keystore).
- Device selection limited to devices bound to user; include JWT in all calls.

## Core Flows
- Pairing: call `/api/pair/init` to create a pairing session; scan agent QR and POST `/api/pair/confirm` with `pair_token`; receive `agent_jwt` for first agent auth.
- Commands: send via Laravel command endpoint; receive command id; subscribe to push/WebSocket updates for status.
- Telemetry: fetch via `/telemetry/latest` with pagination; show compliance badges from `/compliance/status`.
- Alerts: subscribe to push notifications; acknowledge via `/alerts/{id}/ack`.

## Offline and Error Handling
- Cache last known telemetry and compliance state; mark stale after 10 minutes.
- Handle `policy_out_of_sync` by prompting user to refresh; require 2FA for high-risk commands when flagged.
- Show quarantine state clearly with remediation steps and contact to admin.

## Security
- Pin TLS to backend certificates; validate JWT expiry before use.
- Do not store command payloads in logs; redaction for screenshots.
