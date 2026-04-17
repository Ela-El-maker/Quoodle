# quoodle-infra

Infrastructure and deployment assets for Quoodle environments.

This directory carries provisioning, deployment, and operations strategy for non-local environments.

## 1. Architecture Strategy

Infrastructure design goals:

- reproducible environment creation
- strict service boundary control
- safe secret management and rotation
- observable runtime with explicit SLO/SLA instrumentation

## 2. Structure

| Directory | Purpose |
| --- | --- |
| `terraform/` | cloud provisioning and foundation resources |
| `helm/` | Kubernetes packaging and environment overlays |
| `k8s/` | raw manifests for targeted operations |
| `docker/` | container build/runtime helper assets |
| `monitoring/` | metrics, dashboards, alerting policies |
| `logging/` | log ingestion and retention patterns |
| `ci-cd/` | delivery pipeline assets and controls |

## 3. Environment Model

Typical tiers:

- local: developer workstation and docker compose
- dev/staging: shared integration clusters
- production: hardened cluster and managed secret lifecycle

## 4. Deployment Patterns

- immutable image tagging
- environment-specific values overlays
- migration-safe rollout sequencing
- rollback-first deployment planning

## 5. Security and Compliance Focus

- least-privilege IAM and network controls
- secret scoping and rotation
- signing key custody discipline
- audit log retention and access boundaries

## 6. Observability Strategy

Track:

- command latency and failure rates
- queue depth and worker throughput
- agent online presence stability
- webhook error rates
- API auth/session error patterns

## 7. Change Management

When updating infra assets:

- document blast radius
- include rollout and rollback steps
- keep app endpoint contracts aligned with infra changes
- validate in lower environment before promotion

## 8. Local Development Note

For daily local engineering, prefer root `docker compose` flow. Use this folder for deployable environment engineering rather than quick local startup.

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
