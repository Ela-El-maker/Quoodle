# scripts

Operational and development automation scripts for Quoodle.

Scripts in this folder are designed to accelerate repeatable bring-up, verification, and diagnostics.

## 1. Design Principles

- idempotent where possible
- explicit parameters for high-impact actions
- observable outputs for debugging
- safe defaults for local development

## 2. Script Categories

- bootstrap scripts
- e2e validation scripts
- install/config scripts
- diagnostics/verification scripts

## 3. Key Scripts

### `setup_dev.sh`

Bootstraps local docker-based environment.

```bash
./scripts/setup_dev.sh
```

### `run_windows_ring0_e2e.ps1`

Windows-focused end-to-end validation for pairing, dispatch, kernel path, and result return.

```powershell
pwsh .\scripts\run_windows_ring0_e2e.ps1
pwsh .\scripts\run_windows_ring0_e2e.ps1 -KeepAgentRunning
```

### `install_linux_agent_systemd.sh`

Installs and enables Linux agent service units.

```bash
./scripts/install_linux_agent_systemd.sh
```

### `test_telemetry_worker.sh`

Telemetry-path focused checks.

```bash
./scripts/test_telemetry_worker.sh
```

### `preflight_production.ps1`

Validates production env completeness and guardrails before deployment.

```powershell
pwsh .\scripts\preflight_production.ps1 -EnvFile .env.production -ComposeFile docker-compose.prod.yml
```

### `preflight_do_mini.sh`

Linux preflight checks for the DigitalOcean mini deployment path.

```bash
./scripts/preflight_do_mini.sh .env.do-mini docker-compose.do-mini.yml
```

### `bootstrap_do_ubuntu.sh`

Bootstraps an Ubuntu droplet with Docker Engine, Compose plugin, and firewall defaults.

```bash
sudo ./scripts/bootstrap_do_ubuntu.sh
```

## 4. Common Environment Variables

- `LARAVEL_BASE_URL`
- `FASTAPI_BASE_URL`
- `TEST_USER_EMAIL`
- `TEST_USER_PASSWORD`

## 5. Manual End-to-End Strategy

When validating manually:

1. start core backend services
2. ensure agent service online/authenticated
3. pair and claim device
4. issue non-sensitive command
5. verify trace transitions and result
6. issue sensitive/privileged command as needed
7. verify telemetry and audit artifacts

## 6. Safe Usage Guidance

- run from repo root unless script documents otherwise
- read parameters before running high-impact scripts
- keep logs from failed runs for incident and regression analysis
- avoid mixing old runtime artifacts with fresh pairing tests

## 7. Sequence Diagrams

### 7.1 Manual End-to-End Validation

```text
Operator           Control UI/API         Gateway          Agent Service
   |                    |                    |                  |
   | login              |                    |                  |
   |------------------->|                    |                  |
   | pair device        |------------------->|<-----------------|
   | submit command     |------------------->|----------------->|
   | view result        |<-------------------|<-----------------|
```

### 7.2 Windows E2E Script Intent

```text
PowerShell Script     Docker Stack        Agent Service      Assertions
       |                   |                   |                 |
       | start deps        |------------------>|                 |
       | pair + auth check |                   |                 |
       | dispatch command  |------------------>|                 |
       | collect result    |<------------------|                 |
       | assert pass/fail  |                   |---------------> |
```
