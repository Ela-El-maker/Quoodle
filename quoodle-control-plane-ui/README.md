# Quoodle Control Plane UI

Next.js frontend for the Quoodle control plane.

This app replaces Laravel Blade pages while Laravel remains the backend/API service.

## Stack

- Next.js `16.2.2`
- React `19.2.4`
- TypeScript
- Tailwind CSS v4

## Local Setup

1. Install dependencies:

```bash
npm install
```

2. Configure environment:

```bash
cp .env.local.example .env.local
```

3. Start the app:

```bash
npm run dev
```

4. Open:

`http://localhost:3000`

## Backend Integration

- Laravel base URL: `NEXT_PUBLIC_CONTROL_PLANE_BASE_URL`
- Laravel API URL: `NEXT_PUBLIC_CONTROL_PLANE_API_URL`
- Server-side Laravel API URL (for Next route handlers): `CONTROL_PLANE_API_URL`
- Google OAuth Client ID (for auth redirect start route): `GOOGLE_CLIENT_ID`

Default local values target the existing Laravel control-plane service at `http://localhost:8088`.

## Docker Compose

From repo root:

```bash
docker compose up -d --build control-plane control-plane-ui
```

UI will be available at `http://localhost:3000`.
