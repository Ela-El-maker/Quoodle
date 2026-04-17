# quoodle-control-plane

Laravel control plane and trust anchor for Quoodle.

Primary functions:

- authentication and session control
- role-based access control
- pairing token/session workflows
- command authorization and signing handoff
- persistence of device, command, telemetry, and audit state

Stack:

- PHP 8.4
- Laravel 12
- MySQL
- Redis

## 1. Responsibilities

The control plane is the policy and identity source of truth. It decides who can issue what command to which device, records the decision, and coordinates dispatch through the gateway.

## 2. Runtime Dependencies

- MySQL for persistent state
- Redis for queues/cache/sessions (depending on env)
- Gateway reachable for dispatch and webhooks

## 3. Local Run

From `quoodle-control-plane` (standalone mode):

```powershell
composer install
Copy-Item .env.example .env -Force
php artisan key:generate
php artisan migrate
php artisan serve --host=0.0.0.0 --port=8088
```

Recommended local mode is docker-compose from repo root so all services start together.

## 4. Core API Surfaces

Auth/session:

- `POST /api/register`
- `POST /api/login`
- `POST /api/token/refresh`
- `POST /api/logout`
- `GET /api/auth/me`

Pairing:

- `POST /api/pair/init`
- `POST /api/pair/request`
- `POST /api/pair/confirm`
- `GET /api/pair/session/{id}`

Device operations:

- `GET /api/devices`
- `GET /api/devices/{id}`
- `POST /api/devices/{id}/claim`

Command plane:

- `POST /api/commands`
- `GET /api/commands/{id}`
- `GET /api/devices/{id}/commands`

Telemetry/audit/alerts:

- `GET /api/devices/{id}/telemetry/latest`
- `GET /api/audit/device/{id}`
- `GET /api/alerts`
- `POST /api/alerts/{id}/ack`

Note: exact route middleware and role access are defined in route files and policy layers.

## 5. Queue and Dispatch Path

Typical path:

1. Command request accepted by API.
2. Authorization and policy checks.
3. Envelope/signature creation.
4. Enqueue dispatch job.
5. Dispatch to gateway endpoint.
6. Update command state from webhook receipts.

## 6. Project Layout

- `app/Http/Controllers/` request handlers
- `app/Jobs/` async dispatch/workers
- `app/Services/` domain services (pairing, command signing, etc.)
- `app/Models/` persistence models
- `routes/` API and web routes
- `database/migrations/` schema evolution
- `tests/` feature and unit tests

## 7. Security Notes

- Signing material is sensitive; protect keys by environment.
- Do not bypass signature path for command dispatch.
- Maintain strict role boundaries for viewer/operator/admin features.

## 8. Testing

```powershell
php artisan test
```

For targeted suites:

```powershell
php artisan test --filter Pair
php artisan test --filter Command
```

## 9. Ops Troubleshooting

- queue stalled: inspect queue worker and failed jobs table
- webhook drift: inspect gateway logs and signature validation
- command stuck queued: verify gateway reachable and device online/authenticated
- auth redirect loops: verify cookie/session config and `auth/me` responses
