# mvr-api

Tiny FastAPI service that exposes the dynamic endpoints the static
`mvr.ac` landing page needs. Replaces the old Vercel deploy of
`pages/api/contributions.ts`.

## Endpoints

- `GET /healthz` — liveness.
- `GET /contributions` — GitHub contribution calendar for
  `$GITHUB_USER` (defaults to `mvrozanti`), returned as the
  `weeks[]` shape the front-end expects. In-process cache, TTL
  `CACHE_TTL_SECONDS` (default 3600).

## Env

| Var | Required | Default |
|---|---|---|
| `GITHUB_TOKEN` | yes | — (classic PAT, `public_repo` + `read:user`) |
| `GITHUB_USER` | no | `mvrozanti` |
| `CACHE_TTL_SECONDS` | no | `3600` |
| `ALLOWED_ORIGINS` | no | `https://mvr.ac,https://www.mvr.ac,https://mvrozanti.github.io` |
| `MVR_AC` | no | `mvr.ac` (only used for the caddy vhost label) |

`.env.example` is committed; the real `.env` lives at
`/home/opc/mvr-api/.env` on the VPS, gitignored.

## Routing

caddy-docker-proxy puts this behind `https://api.mvr.ac` (no
Authelia gate — it's a fully public read-only proxy in front of
GitHub's GraphQL).

## Hub tile

Internal API, not user-facing — exempted from
`mandragora-audit 05-hub-tile` via the allowlist.
