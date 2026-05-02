# Quoodle Deployment on DigitalOcean Mini Ubuntu Droplet

This guide is optimized for a single small Ubuntu droplet where Quoodle runs as a compact all-in-one stack.

Use this when you want:

- one VM deployment
- local MySQL + Redis containers
- low operational overhead

## 1. Practical Sizing

Recommended baseline:

- 2 vCPU
- 2-4 GB RAM
- 40+ GB SSD

It can run on smaller plans, but image builds and Node/Laravel workloads may become unstable without swap.

## 2. Bootstrap Host

On the droplet:

```bash
git clone <your-fork-or-repo-url> quoodle
cd quoodle
sudo ./scripts/bootstrap_do_ubuntu.sh
```

The bootstrap script installs Docker and opens UFW ports `3000`, `8088`, and `8000`.

Optional but recommended on very small droplets:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 3. Configure Environment

```bash
cp .env.do-mini.example .env.do-mini
```

Fill every placeholder in `.env.do-mini`:

- all `..._B64` signing keys
- `APP_KEY`
- SMTP credentials
- OAuth credentials (if using Google login)
- public URLs for API/UI

For direct-IP bring-up (no TLS yet), set:

- `CONTROL_PLANE_APP_URL=http://<droplet-ip>:8088`
- `CONTROL_PLANE_UI_URL=http://<droplet-ip>:3000`
- `NEXT_PUBLIC_CONTROL_PLANE_BASE_URL=http://<droplet-ip>:8088`
- `NEXT_PUBLIC_CONTROL_PLANE_API_URL=http://<droplet-ip>:8088/api`
- `NEXT_PUBLIC_CONTROL_PLANE_UI_URL=http://<droplet-ip>:3000`
- `AUTH_COOKIE_SECURE=false`
- `CONTROL_PLANE_BIND_IP=0.0.0.0`

## 4. Preflight Validation

```bash
./scripts/preflight_do_mini.sh .env.do-mini docker-compose.do-mini.yml
```

This fails fast on:

- missing required variables
- placeholder values
- unsafe production toggles
- broken compose interpolation

## 5. Deploy

```bash
docker compose --env-file .env.do-mini -f docker-compose.do-mini.yml up -d --build
docker compose -f docker-compose.do-mini.yml ps
```

Default mode is memory-aware:

- scheduler is enabled
- embedded queue worker runs in `control-plane`
- dedicated `control-plane-worker` is disabled by default
- AI sidecar is disabled by default

Enable dedicated worker:

```bash
docker compose --env-file .env.do-mini -f docker-compose.do-mini.yml --profile worker up -d --build
```

Enable AI sidecar:

```bash
docker compose --env-file .env.do-mini -f docker-compose.do-mini.yml --profile ai up -d --build
```

## 6. One-Time Migration Step

Keep `RUN_MIGRATIONS_ON_BOOT=false` and run migrations deliberately:

```bash
docker compose --env-file .env.do-mini -f docker-compose.do-mini.yml exec -T control-plane php artisan migrate --force
```

## 7. Verification

1. UI opens at `CONTROL_PLANE_UI_URL` (or `http://<droplet-ip>:3000` if no reverse proxy yet).
2. Gateway health responds:

```bash
curl http://127.0.0.1:8000/health
```

3. Pair one staging device and run:
   - `collect_system_info`
   - `list_processes`
   - `list_files`
4. Confirm command states reach `completed`.

## 8. Upgrades

```bash
git pull
docker compose --env-file .env.do-mini -f docker-compose.do-mini.yml up -d --build
```

## 9. Rollback

If a release fails, roll back by checking out the previous commit and rebuilding:

```bash
git checkout <known-good-commit>
docker compose --env-file .env.do-mini -f docker-compose.do-mini.yml up -d --build
```
