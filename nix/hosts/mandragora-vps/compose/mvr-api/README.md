# mvr-api

Tiny FastAPI service that exposes the dynamic endpoints the static
`mvr.ac` landing page needs. Replaces the old Vercel deploy of
`pages/api/contributions.ts`.

## Endpoints

- `GET /healthz` — liveness.
- `GET /theme` — the desktop's matugen palette, proxied from
  `host.docker.internal:6684/api/theme?colors=1` over the `tailnet-fwd`
  bridge (`?colors=1` drops the wallpaper path). 5 s in-process cache;
  `503` when the desktop is offline, which `theme.js` treats as "keep
  the fallback tokens". This is how the GitHub-Pages apex `mvr.ac`
  follows the wallpaper: it has no same-origin proxy, so its
  `theme.js` points here cross-origin (CORS already allows the apex).
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
| `THEME_UPSTREAM` | no | `http://host.docker.internal:6684/api/theme` |
| `THEME_TTL_SECONDS` | no | `5` |

`.env.example` is committed; the real `.env` lives at
`/home/opc/mvr-api/.env` on the VPS, gitignored.

## Deploy

`deploy.sh` (deploy-guard) rsyncs the stack and runs
`docker compose up -d --build`: the image is built from `app/`, so a
plain `up -d` would keep serving the old code.

## Routing

caddy-docker-proxy puts this behind `https://api.mvr.ac` (no
Authelia gate — it's a fully public read-only proxy in front of
GitHub's GraphQL).

## Hub tile

Internal API, not user-facing — exempted from
`mandragora-audit 05-hub-tile` via the allowlist.
