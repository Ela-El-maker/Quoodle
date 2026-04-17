# scripts

Operational and development automation scripts for Quoodle.

## 1. Scope

This folder provides helper scripts for:

- local bootstrap
- end-to-end validation
- environment diagnostics
- platform-specific install helpers

## 2. Key Scripts

### `setup_dev.sh`

Bootstraps the local docker-based environment.

```bash
./scripts/setup_dev.sh
```

Typical outcomes:

- containers built and started
- database migrations run where configured
- baseline health checks available

### `run_windows_ring0_e2e.ps1`

Primary Windows end-to-end runner for command path verification.

```powershell
pwsh .\scripts\run_windows_ring0_e2e.ps1
pwsh .\scripts\run_windows_ring0_e2e.ps1 -KeepAgentRunning
```

Validates pairing, auth, dispatch, kernel path, and result loop.

### `install_linux_agent_systemd.sh`

Installs and enables Linux agent services.

```bash
./scripts/install_linux_agent_systemd.sh
sudo systemctl daemon-reload
sudo systemctl restart quoodle-privileged quoodle-agent
```

### `test_telemetry_worker.sh`

Telemetry worker focused checks.

```bash
./scripts/test_telemetry_worker.sh
```

## 3. Common Environment Variables

- `LARAVEL_BASE_URL`
- `FASTAPI_BASE_URL`
- `TEST_USER_EMAIL`
- `TEST_USER_PASSWORD`

## 4. Usage Guidance

- run from repo root unless script says otherwise
- review script parameters before production-like runs
- keep script output logs for debugging command-path failures
