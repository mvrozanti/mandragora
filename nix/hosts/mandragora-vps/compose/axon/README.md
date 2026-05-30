# `axon` — code-graph context engine edge proxy

VPS-side caddy reverse-proxy for `https://axon.mvr.ac`. Two desktop
services back it (per the decouple-UI-from-core directive):

- `axon` (loopback `127.0.0.1:7070`) — the upstream
  [axon](https://github.com/HideakiSolutions/axon) C++ HTTP API.
- `axon-web` (tailnet `100.115.80.79:8081`) — sibling project at
  `~/Projects/axon-web`. Preact SPA + ~150 LoC Node runtime that
  serves the SPA, adds `GET /api/whoami` from forward-auth headers,
  and reverse-proxies the rest of `/api/*` to `axon`.

The VPS terminates TLS, runs Authelia 2FA, and proxies to `axon-web`.

## Why a proxy container

`axon-proxy` is a label-only anchor for caddy-docker-proxy — it
doesn't serve traffic itself. Same shape as `compose/stt` /
`compose/tts` / `compose/kl`.

## Topology

```
browser → axon.mvr.ac (caddy on VPS) → forward_auth(authelia)
       → reverse_proxy → 100.115.80.79:8081  (desktop, axon-web)
            ├── GET /             → static SPA (dist/)
            ├── GET /api/whoami   → echoes Remote-User / Remote-Email
            └── /api/*            → 127.0.0.1:7070  (axon, upstream axon)
```

`axon` only listens on loopback — only `axon-web` is exposed on
the tailnet, so the API can't be hit without going through Authelia
and the whoami layer.

## API (reachable through `https://axon.mvr.ac`)

| method | path                       | who responds | notes                                         |
|--------|----------------------------|--------------|-----------------------------------------------|
| GET    | `/`                        | axon-web     | SPA shell (Preact, Axon Surgical Dark)        |
| GET    | `/api/whoami`              | axon-web     | `{user, email, name, groups[]}` from headers  |
| GET    | `/api/overview`            | axon         | top files + top symbols                       |
| GET    | `/api/graph[?mode=symbol]` | axon         | `{nodes, edges, meta}`                        |
| GET    | `/api/search?q=`           | axon         | files + symbols                               |
| GET    | `/api/symbol/<name>`       | axon         | symbol detail + callers                       |
| POST   | `/api/detect-changes`      | axon         | diff → affected symbols                       |
| GET    | `/api/observations?q=`     | axon         | semantic search / list                        |
| GET    | `/api/capsule?q=…`         | axon         | assembled token-budget context capsule        |
| GET    | `/api/threads`             | axon         | dialogue threads                              |
| GET    | `/api/threads/:id/sessions`| axon         | sessions in a thread                          |
| GET    | `/api/sessions/:id/turns`  | axon         | turns in a session                            |
| GET    | `/api/dialogue/search?q=`  | axon         | semantic search across turns                  |

## Layout on VPS

```
/home/opc/axon/
└── docker-compose.yml         ← repo copy (only file needed)
```

## `.env`

```
MVR_AC=mvr.ac
AXON_UPSTREAM=100.115.80.79:8081
```

## Bring-up

```
rsync -av --delete \
  nix/hosts/mandragora-vps/compose/axon/ \
  opc@mandragora-vps:/home/opc/axon/
ssh opc@mandragora-vps 'cd /home/opc/axon && docker compose up -d'
```

## Followups

- `axon.mvr.ac` must be in `authelia/config/configuration.yml`
  access_control rules (`two_factor`) and authelia must be restarted,
  otherwise the default-deny gives 403.
- Hub tile + `hub/config/services.yaml` entry must be present so
  `mandragora-audit 05-hub-tile` stays green.
- Desktop must run **both** systemd user services:
  - `axon` — needs `axon` on PATH (or `~/.local/bin/axon` or
    `~/Projects/axon/build/axon`),
  - `axon-web` — needs `node` and `~/Projects/axon-web/dist/index.html`
    (cd ~/Projects/axon-web && npm install && npm run build).
