# API Endpoints

Laravel <-> Mobile (REST): register, login, 2fa/verify, token/refresh, logout, devices list/detail/rename, pairing init/confirm, commands CRUD, telemetry latest/history, updates listing, alerts list/ack, audit trail.
Laravel <-> FastAPI (REST/Webhook):
- Laravel -> FastAPI: POST /api/v1/command/dispatch, /policy/push, /update/deploy
- FastAPI -> Laravel: POST /api/v1/webhook/device/online, /device/offline, /command/result, /command/ack, /telemetry/summary, /security/attestation
See JSON specs in docs/specs for shapes; controllers/routers now match fields exactly.
