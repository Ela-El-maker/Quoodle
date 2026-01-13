# FastAPI Services Overview

Service folders map to key control-plane responsibilities and should include routers, background tasks, schemas, and integration stubs for Kafka/Redis Streams.

- `policy_resolver/`: Pulls signed policy bundles from Laravel, caches validated rules, and exposes a resolver for command decisions.
- `ota_manager/`: Manages OTA manifests, rollout state, binary signature verification, and agent update scheduling.
- `risk_scorer/`: Aggregates telemetry, correlates events, and upgrades severity for alert routing.
- `eventbus/`: Shared producer/consumer utilities, topic schemas, and consumer-group configurations.
- `quarantine_handler/`: Enforces quarantine rules, command-block lists, and agent exception handling during restricted mode.
