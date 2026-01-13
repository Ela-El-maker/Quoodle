# Sequence Flows

Phases 1-10 are implemented following Development Flow.md:
- Phase 1: Laravel auth + CA bootstrap (JWT/JWKS, certificate stubs)
- Phase 2: FastAPI WSS AUTH path implemented with spec-compliant envelopes
- Phase 3: Windows Agent AUTH handshake + session caching
- Phase 4: Heartbeat + telemetry validated and forwarded upstream
- Phase 5: Command dispatch wired Laravel -> FastAPI -> Agent with ACK
- Phase 6: KernelService opcode skeleton + IOCTL request/response schema
- Phase 7: COMMAND_RESULT forwarded via webhook and appended to audit chain
- Phase 8: Mobile skeleton screens for login/devices/pairing/commands/alerts/updates
- Phase 9: OTA announce + update_status end-to-end
- Phase 10: Policy/compliance/audit plumbing present in Laravel + FastAPI
