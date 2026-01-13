# Laravel Modules Overview

This folder groups domain-specific modules that map to the JSON specs and planned service boundaries. Each module should expose a Laravel package-style structure (controllers, jobs, policies, services) so it can be developed and tested independently.

## Modules
- `policy/`: Policy authoring, validation, publishing, and cache invalidation hooks for FastAPI.
- `compliance/`: Compliance evaluations, scheduled checks, and incident export to the compliance dashboard.
- `attestation/`: Certificate issuance, OCSP/CRL checks, and attestation verification helpers shared with the agent handshake.
- `ota/`: OTA manifest ingestion, rollout rules, binary provenance storage, and rollback handling.
- `risk/`: Risk scoring, correlation logic, and alert severity upgrades for telemetry anomalies.
- `audit-chain/`: Tamper-evident audit log writers, hash-chaining, and export to long-term storage.
