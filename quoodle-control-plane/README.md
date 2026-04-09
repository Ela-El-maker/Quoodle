# quoodle-control-plane

Root of trust for the Quoodle system. Handles identity, certificate authority, policy engine, command authorization, and tamper-evident audit logging.

**Stack:** Laravel / PHP 8.4

## Build & Run

**Prerequisites:** PHP 8.4+, Composer, MySQL 8.0+, Redis

For Docker/dev-stack runs, secrets and keys are centralized in repo-root `.env`.
Use this local `.env.example` only when running Laravel standalone.

```bash
composer install
cp .env.example .env
php artisan key:generate
php artisan migrate
php artisan quoodle:keys:generate   # Ed25519 system keys
php artisan serve
```

Or via Docker from the repo root:

```bash
# centralized env source of truth
cp .env.example .env

./scripts/setup_dev.sh
```

### TLS (Docker)

```bash
docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d --build
```

Expects `certs/control-plane.crt` and `certs/control-plane.key`.

## API Endpoints

### Auth

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/register` | User registration |
| `POST` | `/api/login` | Login with JWT |
| `POST` | `/api/token/refresh` | Refresh JWT |
| `POST` | `/api/logout` | Invalidate session |
| `POST` | `/api/2fa/setup` | Setup 2FA |
| `POST` | `/api/2fa/verify` | Verify 2FA code |

### Devices

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/devices` | List all devices |
| `GET` | `/api/devices/{id}` | Device details |
| `POST` | `/api/devices/{id}/claim` | Claim device ownership |
| `POST` | `/api/pair/init` | Initialize pairing |
| `POST` | `/api/pair/confirm` | Confirm pairing |
| `POST` | `/api/agent/token` | Generate agent JWT |

### Commands

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/commands` | Execute command on device |
| `GET` | `/api/commands/{id}` | Command status |
| `GET` | `/api/devices/{id}/commands` | Device command history |

### Telemetry & Audit

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/devices/{id}/telemetry/latest` | Latest telemetry |
| `GET` | `/api/audit/device/{id}` | Device audit trail |
| `POST` | `/api/audit/append` | Append audit entry |

### Alerts & Compliance

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/alerts` | List alerts |
| `POST` | `/api/alerts/{id}/ack` | Acknowledge alert |
| `POST` | `/api/compliance/evaluate` | Evaluate compliance |
| `POST` | `/api/policy/validate_bundle` | Validate policy bundle |

## Project Structure

```
app/
├── Http/Controllers/    # API controllers
├── Models/              # Eloquent models
├── Services/            # Business logic (signing, audit, compliance)
├── Providers/           # Service providers
└── ...
config/                  # Laravel configuration
database/migrations/     # Database schema
routes/api.php           # API route definitions
tests/                   # PHPUnit tests
```

## Security

- Stores CA private key and Command Signing key — protect via KMS/HSM in production
- Trusted by gateway (webhook signature) and agents (CA chain)
- All commands are Ed25519-signed before dispatch
