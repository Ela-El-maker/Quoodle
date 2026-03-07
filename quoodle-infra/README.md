# quoodle-infra

Infrastructure configuration for deploying and operating Quoodle.

## Structure

| Directory     | Purpose                                                |
| ------------- | ------------------------------------------------------ |
| `terraform/`  | Cloud provisioning — RDS, S3, KMS, networking          |
| `helm/`       | Kubernetes Helm charts for all services                |
| `k8s/`        | Raw Kubernetes manifests (MySQL, secrets)              |
| `docker/`     | Dockerfiles and compose overrides per service          |
| `monitoring/` | Prometheus rules, Grafana dashboards, alert routes     |
| `logging/`    | Log collectors (Fluent Bit), retention, index mappings |
| `ci-cd/`      | Build pipelines, signing steps, SBOM generation        |

## Local Development

```bash
./scripts/setup_dev.sh
```

Uses `docker-compose.yml` at the repo root to orchestrate Laravel, FastAPI, MySQL, and Redis.

## Production

Kubernetes deployment uses Helm charts in `helm/` with environment-specific values files. Secrets are managed via KMS-backed Sealed Secrets.
