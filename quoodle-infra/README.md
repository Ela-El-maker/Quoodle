# quoodle-infra

Infrastructure and deployment assets for Quoodle environments.

## 1. Purpose

This directory contains infra-as-code and operational packaging resources used to provision, deploy, and operate Quoodle outside local development.

## 2. Structure

| Directory | Purpose |
| --- | --- |
| `terraform/` | Cloud resource provisioning (network, storage, managed services, security controls) |
| `helm/` | Kubernetes chart templates and values |
| `k8s/` | Raw manifests for direct cluster operations |
| `docker/` | Container build and compose support assets |
| `monitoring/` | Metrics, alerts, and dashboard definitions |
| `logging/` | Log shipping and retention configuration |
| `ci-cd/` | Pipeline scaffolding and supply-chain steps |

## 3. Environments

Typical targets:

- local development (docker-compose from repo root)
- shared dev/staging clusters
- production clusters with managed secret workflows

## 4. Operational Focus Areas

- reproducible provisioning
- service-to-service network boundaries
- secret handling and rotation paths
- observability baselines (health, queue, latency, error budgets)
- backup and disaster recovery hooks

## 5. Local Dev Note

For daily local engineering, use repo root compose flow rather than provisioning assets in this folder.

## 6. Change Management Guidance

When editing infra assets:

- keep service ports/endpoints aligned with application configs
- version environment changes with clear migration notes
- validate rollout and rollback paths
- keep least-privilege defaults
