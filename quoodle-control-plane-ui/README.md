# quoodle-control-plane-ui

Next.js control console for Quoodle operators and viewers.

Primary functions:

- authentication and session UI
- role-based route surfaces (viewer/operator/admin)
- pairing and ownership workflow UX
- device management and telemetry views
- command trace, results, and audit exploration

Stack:

- Next.js 16
- React 19
- TypeScript
- Tailwind CSS

## 1. Local Development

From `quoodle-control-plane-ui`:

```powershell
npm install
Copy-Item .env.local.example .env.local -Force
npm run dev
```

Open: `http://localhost:3000`

## 2. Environment Contract

Key values:

- `NEXT_PUBLIC_CONTROL_PLANE_BASE_URL`
- `NEXT_PUBLIC_CONTROL_PLANE_API_URL`
- `CONTROL_PLANE_API_URL` (server-side handlers)
- `GOOGLE_CLIENT_ID` (if OAuth path enabled)

Default local target is control plane on `http://localhost:8088`.

## 3. Runtime Behavior

- UI reads session state via auth endpoints.
- Role guards enforce route accessibility.
- Pairing flows surface token/QR and ownership confirm states.
- Command views visualize dispatch lifecycle through backend state.

## 4. Key UX Domains

- Viewer console
- Operator console
- Device management
- Command compose/trace/results
- Telemetry monitoring
- Alerts and compliance
- Audit trails

## 5. Build and Production Run

```powershell
npm run build
npm run start
```

## 6. Docker Mode

From repo root:

```powershell
docker compose up -d --build control-plane-ui
```

Service is exposed on `http://localhost:3000`.

## 7. Troubleshooting

- login loop: verify `/api/auth/me` behavior and cookies
- empty devices: verify control plane device API and pairing state
- stale status: verify polling cadence and backend lifecycle updates
- pairing modal stuck: inspect pair session endpoints and gateway callbacks
