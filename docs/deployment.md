# Quoodle Production Deployment Runbook

This guide is the production baseline for running Quoodle as decoupled services.

It is intentionally separate from local installation in [`docs/install.md`](./install.md).

For a compact single-node DigitalOcean deployment path (local MySQL/Redis, build-on-host), see:
[`docs/deployment-do-mini.md`](./deployment-do-mini.md).

## 1. Deployment Topology (Decoupled)

Production services are split into independent runtime roles:

- `control-plane` (Laravel web/API)
- `control-plane-scheduler` (cron/scheduler role)
- `control-plane-worker` (queue worker role)
- `gateway` (FastAPI dispatch plane)
- `control-plane-ui` (Next.js operator console)
- `ai-sidecar` (optional profile)

External dependencies (managed services recommended):

- MySQL (RDS/Cloud SQL/etc.)
- Redis (ElastiCache/MemoryStore/etc.)
- TLS termination/load balancer (or edge proxy)

## 2. Files Introduced for Production

- `docker-compose.prod.yml`: decoupled runtime stack for production.
- `.env.production.example`: production-safe environment template.
- `scripts/preflight_production.ps1`: preflight checks before deploy.

## 3. One-Time Preparation

1. Build and publish versioned images (or use your registry pipeline).
2. Copy `.env.production.example` to `.env.production`.
3. Replace every placeholder with real secret/config values.
4. Keep `.env.production` out of git.

## 4. Preflight Checks

From repo root:

```powershell
cd C:\path\to\Quoodle
.\scripts\preflight_production.ps1 -EnvFile .env.production -ComposeFile docker-compose.prod.yml
```

What it checks:

- required keys exist
- no obvious placeholders remain
- production guardrails (debug/dev fallback/test endpoints)
- compose renders successfully

## 5. Deploy

```powershell
docker compose --env-file .env.production -f docker-compose.prod.yml pull
docker compose --env-file .env.production -f docker-compose.prod.yml up -d
docker compose --env-file .env.production -f docker-compose.prod.yml ps
```

Enable AI sidecar only when needed:

```powershell
docker compose --env-file .env.production -f docker-compose.prod.yml --profile ai up -d
```

## 6. Migration Strategy (Recommended)

Do not run schema migrations automatically on every web boot in production.

Use controlled rollout:

1. Set `RUN_MIGRATIONS_ON_BOOT=false` in `.env.production`.
2. Run migrations once during release window:

```powershell
docker compose --env-file .env.production -f docker-compose.prod.yml exec -T control-plane php artisan migrate --force
```

3. Verify app health and command flow.

## 7. Post-Deploy Verification

1. UI reachable at `CONTROL_PLANE_UI_URL`.
2. Gateway health:

```powershell
curl http://<gateway-host>:<gateway-port>/health
```

3. Command capability check from UI.
4. End-to-end command test on a paired staging device:
   - `collect_system_info`
   - `list_processes`
   - `list_files`
5. Verify command states progress to `completed`.

## 8. Scaling Guidance

- Scale web/API separately from queue worker:
  - increase `control-plane` replicas for API traffic.
  - increase `control-plane-worker` replicas for command throughput.
- Keep scheduler as singleton.
- Keep gateway scaling behind sticky/session-aware edge strategy for WebSocket workloads.

## 9. Rollback

Rollback is image-tag based:

1. Set previous known-good tags in `.env.production`:
   - `CONTROL_PLANE_TAG`
   - `CONTROL_PLANE_UI_TAG`
   - `GATEWAY_TAG`
   - `AI_SIDECAR_TAG` (if used)
2. Re-deploy:

```powershell
docker compose --env-file .env.production -f docker-compose.prod.yml up -d
```

## 10. Security Minimums

- `APP_DEBUG=false`
- `ALLOW_DEV_SIG_FALLBACK=false`
- `ENABLE_TEST_ENDPOINTS=false`
- `REQUIRE_ED25519=true`
- `REQUIRE_LARAVEL_SIGNATURE=true`
- `REQUIRE_FASTAPI_SIGNATURE=true`
- keep all private keys in managed secrets, not plaintext files in repo

## 11. Operator Notes

- Local/dev bootstrap behavior (auto-seed, embedded worker) is now configurable:
  - `SEED_LOCAL_ADMIN_ON_BOOT`
  - `RUN_QUEUE_WORKER_IN_WEB`
- Production should use:
  - `SEED_LOCAL_ADMIN_ON_BOOT=false`
  - `RUN_QUEUE_WORKER_IN_WEB=false`
  - dedicated `control-plane-worker` service
