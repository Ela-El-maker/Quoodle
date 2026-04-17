# quoodle-infra

Infrastructure strategy assets for Quoodle.

This folder is now intentionally lean. It keeps only the infra content that is actively useful and non-duplicative with the runtime codebase.

## 1. What This Folder Owns

- Terraform foundations for cloud resource provisioning.
- Monitoring baselines for Prometheus/Grafana/Alertmanager.

## 2. What Was Removed (on purpose)

The following stale placeholder assets were removed to avoid drift and confusion:

- stub CI/CD workflows under `ci-cd/`
- duplicate/empty `cicd/`
- toy Kubernetes manifests under `k8s/`
- empty placeholder folders `helm/` and `logging/`
- infra-local Docker compose and Dockerfiles (already removed in prior cleanup)

## 3. Current Structure

| Directory | Purpose |
| --- | --- |
| `terraform/` | Cloud provisioning and foundation resources |
| `monitoring/` | Metrics, dashboards, and alerting baseline configs |

## 4. Canonical Runtime Container Layout

Container runtime source of truth is at repo root and service folders, not in `quoodle-infra`:

- `docker-compose.yml`
- `docker-compose.tls.yml`
- `quoodle-control-plane/Dockerfile`
- `quoodle-control-plane-ui/Dockerfile`
- `quoodle-gateway/Dockerfile`

## 5. Terraform Scope

`terraform/` contains starter resources for:

- core provider wiring
- KMS keys
- S3 artifacts bucket/object
- RDS MySQL instance

These should be treated as baseline templates and hardened per environment (state backend, naming, IAM, secrets injection, and tagging policy).

## 6. Monitoring Scope

`monitoring/` includes minimal configs for:

- Prometheus scrape/target basics
- Grafana datasource baseline
- Alertmanager starter configuration

Use these as seed configs and promote environment-specific versions in your deployment platform.

## 7. Environment Model

- local: use root `docker compose` only
- shared dev/staging: provision with Terraform + platform-native deploy tooling
- production: hardened IAM, managed secrets, strict rollout/rollback guardrails

## 8. Change Management Rules

When editing this folder:

- avoid introducing duplicate runtime definitions already owned elsewhere
- keep endpoint and port assumptions aligned with root compose/services
- document blast radius and rollback steps in PR notes
- validate in lower environments before production promotion

## 9. Sequence Diagrams

### 9.1 Environment Rollout Pipeline

```text
Git Commit      CI/CD Pipeline      Container Registry      Cluster
    |                 |                     |                  |
    | push            | build+test          |                  |
    |---------------->|-------------------->| publish image    |
    |                 | deploy chart/manif. |----------------->|
    |                 | verify health       |                  |
```

### 9.2 Rollback Pattern

```text
Monitoring Alert      Ops Action         Deploy System
       |                  |                   |
       | error budget hit |                   |
       |----------------->| rollback request  |
       |                  |------------------>| previous revision
       |                  | verify recovery   |
```
