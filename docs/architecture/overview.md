# Architecture Overview

This monorepo contains all components for the Secure Device Control System. Core services:
- Laravel backend: auth, CA, policy, audit
- FastAPI controller: WSS gateway, telemetry pipeline, command router, OTA coordinator
- Windows Agent: WSS client, telemetry producer, IOCTL bridge
- KernelService: privileged executor for opcodes
- Mobile App: Flutter UI for login, devices, pairing, commands, updates
- Infrastructure: Docker, k8s, Terraform, CI/CD, monitoring

Each service aligns to the canonical specs in docs/specs/ and the flows defined in README.md and Development Flow.md.
