# System Diagrams (text)

Sequence summary (see docs/specs/System flow.json for full details):
1. Mobile -> Laravel: register/login, pairing initiation
2. Agent -> FastAPI (WSS): AUTH -> AUTH_ACK, heartbeat/telemetry
3. Laravel -> FastAPI: /command/dispatch, /policy/push, /update/deploy
4. FastAPI -> Agent (WSS): COMMAND_DELIVERY, UPDATE_ANNOUNCE, POLICY_UPDATE
5. Agent -> KernelService: IOCTL per WindowsAgent + KernelService Interface.json
6. Agent -> FastAPI: COMMAND_ACK, COMMAND_RESULT, UPDATE_STATUS, TELEMETRY
7. FastAPI -> Laravel: webhooks for device online/offline, command ACK/RESULT, telemetry summary
8. Laravel -> Mobile: REST + notifications for commands, telemetry, updates, alerts
