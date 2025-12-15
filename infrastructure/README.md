# Infrastructure Layout

- `terraform/`: Cloud account scaffolding, network perimeters, Redis/MySQL/Kafka clusters, and secret backends.
- `helm/`: Service charts (Laravel, FastAPI, agent-gateway), values files per environment, and shared templates.
- `monitoring/`: Prometheus rules, Grafana dashboards, alert routes, and SLO definitions.
- `logging/`: Log collectors (Fluent Bit/Vector), retention rules, and index mappings.
- `cicd/`: Build pipelines, signing steps, SBOM generation, and promotion workflows (dev → staging → prod).
