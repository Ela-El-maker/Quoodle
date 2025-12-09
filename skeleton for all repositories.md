# 🚀 FULL PROJECT STRUCTURE — ALL REPOS (Complete Skeleton v2)

This is the canonical folder layout for the **Secure Device Control System (Academic Simulation)** monorepo + all component repos.

---

============================================================

# 🏠 0. monorepo root

============================================================

```text
secure-device-control/
│
├── backend-laravel/        # Laravel API, CA, policy engine, dashboards
├── backend-fastapi/        # FastAPI WSS controller, router, telemetry gateway
├── windows-agent/          # User-mode Windows agent (C++23)
├── kernel-service/         # Privileged service / driver (C / C++)
├── mobile-app/             # Flutter mobile client
├── infrastructure/         # Docker, k8s, Terraform, CI/CD, monitoring
├── docs/                   # Architecture, specs, threat model, report
│
├── .github/                # Global GitHub Actions (monorepo-level)
│   ├── workflows/
│   │   ├── ci_backend.yml
│   │   ├── ci_agent.yml
│   │   └── ci_mobile.yml
│   └── CODEOWNERS
│
├── .vscode/                # Recommended editor settings
│   └── settings.json
│
├── .editorconfig
├── .gitignore
├── LICENSE
└── README.md               # High-level overview + links into docs & repos


============================================================

# 📌 **1. backend-laravel (PHP/Laravel 12)**

============================================================

```
backend-laravel/
│
├── app/
│   ├── Console/
│   ├── Exceptions/
│   ├── Http/
│   │   ├── Controllers/
│   │   │   ├── Auth/
│   │   │   │   ├── LoginController.php
│   │   │   │   ├── RegisterController.php
│   │   │   │   └── TwoFAController.php
│   │   │   ├── Devices/
│   │   │   │   ├── DeviceController.php
│   │   │   │   └── PairingController.php
│   │   │   ├── Commands/
│   │   │   │   ├── CommandController.php
│   │   │   │   └── ArtifactController.php
│   │   │   ├── OTA/
│   │   │   │   └── UpdateController.php
│   │   │   ├── Alerts/
│   │   │   │   └── AlertsController.php
│   │   │   └── Compliance/
│   │   │       └── ComplianceController.php
│   │   ├── Middleware/
│   │   └── Requests/
│   ├── Models/
│   │   ├── User.php
│   │   ├── Device.php
│   │   ├── Command.php
│   │   ├── Telemetry.php
│   │   ├── Policy.php
│   │   └── AuditLog.php
│   ├── Services/
│   │   ├── CA/
│   │   │   ├── CertificateAuthority.php
│   │   │   ├── CSRGenerator.php
│   │   │   └── DeviceCertificateIssuer.php
│   │   ├── JWT/
│   │   │   ├── JWTSigner.php
│   │   │   ├── JWKSManager.php
│   │   │   └── KeyRotationService.php
│   │   ├── PolicyEngine/
│   │   │   ├── PolicyEvaluator.php
│   │   │   └── Rules/
│   │   │       ├── CommandRules.php
│   │   │       ├── DeviceRules.php
│   │   │       ├── TimeRules.php
│   │   │       ├── RateRules.php
│   │   │       └── EthicalRules.php
│   │   ├── CommandRegistry/
│   │   │   ├── CommandDefinition.php
│   │   │   └── Registry.php
│   │   ├── OTA/
│   │   │   ├── ReleaseManager.php
│   │   │   └── ManifestValidator.php
│   │   ├── Telemetry/
│   │   │   └── TelemetryIngestService.php
│   │   ├── Compliance/
│   │   │   └── ComplianceChecker.php
│   │   └── AuditTrail/
│   │       ├── AuditWriter.php
│   │       └── AuditHasher.php
│   ├── Traits/
│   └── Helpers/
│
├── bootstrap/
├── config/
│   ├── app.php
│   ├── jwt.php
│   ├── ca.php
│   ├── policy.php
│   ├── telemetry.php
│   ├── audit.php
│   ├── queue.php
│   ├── logging.php
│   └── services.php
│
├── database/
│   ├── migrations/
│   ├── seeders/
│   └── factories/
│
├── resources/
│   ├── views/              # Admin dashboard / research UI (Blade or Inertia/Vue)
│   └── js/                 # If you use Vue/React for web dashboard
│
├── routes/
│   ├── api.php             # Auth, pairing, commands, artifacts, mobile API
│   ├── web.php             # Dashboard, admin UI
│   └── websockets.php      # Optional WSS routes if using websockets in Laravel
│
├── storage/
├── tests/
│   ├── Feature/
│   └── Unit/
│
├── docker/
│   ├── Dockerfile
│   └── nginx.conf
│
├── .env.example
├── composer.json
└── README.md

```

---

============================================================

# ⚡ **2. backend-fastapi (Python/FastAPI)**

============================================================

```
backend-fastapi/
│
├── app/
│   ├── main.py
│   ├── config.py           # Settings (Redis, JWKS, TLS, rate limits)
│   ├── ws/
│   │   ├── connection_manager.py
│   │   ├── auth.py
│   │   ├── protocol.py
│   │   ├── handlers/
│   │   │   ├── auth_handler.py
│   │   │   ├── heartbeat_handler.py
│   │   │   ├── telemetry_handler.py
│   │   │   ├── command_delivery_handler.py
│   │   │   ├── command_ack_handler.py
│   │   │   ├── command_result_handler.py
│   │   │   ├── update_handler.py
│   │   │   └── alert_handler.py
│   │   └── schemas/
│   │       ├── envelope.py
│   │       ├── auth.py
│   │       ├── telemetry.py
│   │       ├── commands.py
│   │       └── updates.py
│   ├── api/
│   │   ├── routes/
│   │   │   ├── device.py       # /webhook/device online/offline, etc.
│   │   │   ├── admin.py
│   │   │   ├── ota.py
│   │   │   ├── webhooks.py     # From Laravel
│   │   │   └── test.py         # Fault injection endpoints
│   │   └── schemas/
│   ├── services/
│   │   ├── redis_service.py
│   │   ├── jwks_service.py
│   │   ├── telemetry_pipeline.py
│   │   ├── command_router.py
│   │   ├── presence_tracker.py
│   │   └── alert_service.py
│   ├── workers/
│   │   ├── command_worker.py
│   │   ├── telemetry_worker.py
│   │   ├── dlq_worker.py
│   │   └── alert_worker.py
│   └── utils/
│       ├── logging.py
│       └── backoff.py
│
├── tests/
│   ├── test_auth.py
│   ├── test_command_dispatch.py
│   ├── test_telemetry.py
│   └── test_update_flow.py
│
├── scripts/
│   ├── run_workers.sh
│   └── sync_jwks.sh
│
├── docker/
│   └── Dockerfile
│
├── pyproject.toml
├── .env.example
└── README.md

```

---

============================================================

# 🪟 **3. windows-agent (C++23)**

============================================================

```
windows-agent/
│
├── src/
│   ├── main.cpp
│   ├── ws/
│   │   ├── ws_client.cpp
│   │   ├── ws_client.hpp
│   │   ├── ws_protocol.cpp
│   │   ├── ws_protocol.hpp
│   │   └── handlers/
│   │       ├── auth_handler.cpp
│   │       ├── command_handler.cpp
│   │       ├── telemetry_handler.cpp
│   │       └── error_handler.cpp
│   ├── kernel/
│   │   ├── ioctl_client.cpp
│   │   ├── ioctl_client.hpp
│   │   └── kernel_schema.hpp
│   ├── crypto/
│   │   ├── ed25519_sign.cpp
│   │   ├── ed25519_sign.hpp
│   │   ├── json_canonicalizer.cpp
│   │   └── json_canonicalizer.hpp
│   ├── storage/
│   │   ├── sqlite_queue.cpp
│   │   └── sqlite_queue.hpp
│   ├── telemetry/
│   │   ├── telemetry_collector.cpp
│   │   └── telemetry_collector.hpp
│   ├── utils/
│   │   ├── base64.cpp
│   │   └── logger.cpp
│   ├── config/
│   │   └── config.hpp
│   └── policy/
│       └── policy_bundle_cache.cpp
│
├── include/
│
├── tests/
│   ├── test_signature.cpp
│   ├── test_ws.cpp
│   └── test_ioctl.cpp
│
├── scripts/
│   ├── install_service.ps1
│   ├── uninstall_service.ps1
│   └── package_agent.ps1
│
├── cmake/
│   └── modules/
│
├── CMakeLists.txt
└── README.md

```

---

============================================================

# 🔧 **4. kernel-service (C / C++)**

============================================================

```
kernel-service/
│
├── service/
│   ├── main.cpp
│   ├── dispatcher.cpp
│   ├── dispatcher.hpp
│   ├── opcodes/
│   │   ├── lock_screen.cpp
│   │   ├── reboot.cpp
│   │   ├── shutdown.cpp
│   │   ├── logout.cpp
│   │   ├── process_list.cpp
│   │   ├── attestation.cpp
│   │   ├── tamper_check.cpp
│   │   ├── stage_update.cpp
│   │   └── commit_update.cpp
│   ├── validation/
│   │   ├── schema_validator.cpp
│   │   └── schema_validator.hpp
│   ├── crypto/
│   │   ├── ed25519_verify.c
│   │   ├── ed25519_verify.h
│   │   └── json_canonicalizer.c
│   └── utils/
│       └── logger.cpp
│
├── driver/                 # Optional kernel driver, if you go that route
│   └── ...
│
├── tests/
│   ├── test_opcodes.cpp
│   └── test_security.cpp
│
├── scripts/
│   ├── build_service.ps1
│   └── build_driver.ps1
│
├── CMakeLists.txt
└── README.md

```

---

============================================================

# 📱 **5. mobile-app (Flutter)**

============================================================

```
mobile-app/
│
├── lib/
│   ├── main.dart
│   ├── config/
│   │   └── environment.dart
│   ├── screens/
│   │   ├── auth/
│   │   │   ├── login_screen.dart
│   │   │   ├── register_screen.dart
│   │   │   └── twofa_screen.dart
│   │   ├── devices/
│   │   │   ├── device_list_screen.dart
│   │   │   ├── device_detail_screen.dart
│   │   │   └── telemetry_view.dart
│   │   ├── pairing/
│   │   │   └── qr_scan_screen.dart
│   │   ├── commands/
│   │   │   ├── send_command_screen.dart
│   │   │   └── command_history_screen.dart
│   │   ├── alerts/
│   │   │   └── alerts_screen.dart
│   │   └── settings/
│   │       └── settings_screen.dart
│   ├── services/
│   │   ├── api_service.dart
│   │   ├── auth_service.dart
│   │   ├── websocket_service.dart
│   │   └── telemetry_service.dart
│   ├── models/
│   │   ├── device.dart
│   │   ├── telemetry.dart
│   │   ├── command.dart
│   │   └── alert.dart
│   ├── utils/
│   │   ├── json_canonicalizer.dart
│   │   └── signature_utils.dart
│   └── widgets/
│
├── test/
├── assets/
│   ├── icons/
│   └── images/
│
├── pubspec.yaml
└── README.md

```

---

============================================================

# ☁️ **6. infrastructure (DevOps / IaC)**

============================================================

```
infrastructure/
│
├── docker-compose.yml
│
├── docker/
│   ├── laravel/
│   │   └── Dockerfile
│   ├── fastapi/
│   │   └── Dockerfile
│   ├── agent/
│   │   └── Dockerfile
│   └── mobile/
│       └── Dockerfile
│
├── k8s/
│   ├── laravel-deployment.yaml
│   ├── fastapi-deployment.yaml
│   ├── redis.yaml
│   ├── mysql.yaml
│   ├── minio.yaml
│   └── ingress.yaml
│
├── terraform/
│   ├── main.tf
│   ├── providers.tf
│   ├── s3.tf
│   ├── rds.tf
│   ├── kms.tf
│   └── ecs_or_gke.tf
│
├── ci-cd/
│   ├── github-actions/
│   │   ├── deploy_laravel.yml
│   │   ├── deploy_fastapi.yml
│   │   ├── build_agent.yml
│   │   └── build_mobile.yml
│   └── scripts/
│       ├── run_tests.sh
│       └── db_migrate.sh
│
└── monitoring/
    ├── prometheus/
    ├── grafana/
    └── alertmanager/

```

---

============================================================

# 📘 **7. docs (Documentation)**

============================================================

```
docs/
|
├── specs/                       # All canonical JSON specifications
│   ├── FastAPI ↔ Laravel (REST + Webhook Control Channel).json
│   ├── Full System Json.json
│   ├── Laravel ↔ Mobile App (REST + notifications).json
│   ├── MasterBlueprint-v3.json
│   ├── Missing System Components.json
│   ├── System flow.json
│   ├── WindowsAgent ↔ FastAPI (WSS control channel).json
│   └── WindowsAgent ↔ KernelService Interface.json
│
├── architecture/
│   ├── overview.md              # High-level picture (actors, components)
│   ├── system_diagrams.md       # ASCII/PlantUML diagrams
│   ├── sequence_flows.md        # Narrative of flows (based on System flow + Full System Json)
│   ├── threat_model.md
│   ├── trust_model.md
│   └── key_management.md
│
├── protocols/
│   ├── ws_protocol.md           # Agent ↔ FastAPI (from WSS JSON spec)
│   ├── ioctl_protocol.md        # Agent ↔ KernelService IOCTL schema
│   ├── api_endpoints.md         # Laravel + FastAPI REST endpoints
│   └── command_envelope_spec.md # Universal message/envelope fields
│
├── onboarding/
│   ├── setup_env.md             # How to run the whole stack locally
│   ├── contribution_guide.md
│   └── coding_standards.md
│
├── security/
│   ├── audit_chain.md           # Hash-chained audit logs design
│   ├── compliance_rules.md      # Device posture & periodic checks
│   └── revocation_flow.md       # Key/cert revocation & emergency flows
│
└── report/                      # (Optional) Academic report structure
    ├── 01-introduction.md
    ├── 02-architecture.md
    ├── 03-security_model.md
    ├── 04-implementation.md
    └── 05-results_and_future_work.md

```

---

# 🎉 **ALL REPOSITORIES STRUCTURED SUCCESSFULLY**

---

