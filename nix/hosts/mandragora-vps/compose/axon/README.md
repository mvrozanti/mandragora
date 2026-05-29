# `axon` — code-graph context engine edge proxy

VPS-side caddy reverse-proxy for `https://axon.mvr.ac`. Real engine
(axon C++ HTTP API + in-repo Preact SPA) lives on the desktop as a
systemd user service `axon-core`, bound to the tailscale IP on port
7070.

## Why a proxy container

Same decouple-UI-from-core pattern as `stt` / `tts` / `kl`: axon needs
the indexed DuckDB DB and the user's source trees, both of which live
on the desktop. The VPS terminates TLS, runs Authelia 2FA, and proxies
through to the desktop. The `axon-proxy` container is a label-only
anchor for caddy-docker-proxy — it doesn't serve traffic itself.

## Topology

```
browser → axon.mvr.ac (caddy on VPS) → forward_auth(authelia)
       → reverse_proxy → 100.115.80.79:7070  (desktop, axon-core)
       → ./axon serve --http --all --web-root=web/dist
       → SPA (Preact)  + REST API + DuckDB graph
```

## API (on `axon-core`, also reachable through `https://axon.mvr.ac`)

| method | path                       | body / response                                       |
|--------|----------------------------|-------------------------------------------------------|
| GET    | `/api/whoami`              | `{user, email, name, groups[]}` (from Authelia headers) |
| GET    | `/api/overview`            | `{top_files, top_symbols}`                            |
| GET    | `/api/graph[?mode=symbol]` | `{nodes, edges, meta}`                                |
| GET    | `/api/search?q=`           | `{files, symbols}`                                    |
| GET    | `/api/symbol/<name>`       | symbol detail + callers                               |
| POST   | `/api/detect-changes`      | `{ref}` → diff → affected symbols                     |
| GET    | `/api/observations?q=`     | semantic search / list                                |
| GET    | `/api/capsule?q=…`         | assembled token-budget context capsule                |
| GET    | `/api/threads`             | dialogue threads                                      |
| GET    | `/api/threads/:id/sessions`| sessions in a thread                                  |
| GET    | `/api/sessions/:id/turns`  | turns in a session                                    |
| GET    | `/api/dialogue/search?q=`  | semantic search across turns                          |
| GET    | `/` (and any non-`/api/*`) | SPA — Axon Surgical Dark UI                           |

## Layout on VPS

```
/home/opc/axon/
└── docker-compose.yml         ← repo copy (only file needed)
```

## `.env`

```
MVR_AC=mvr.ac
AXON_UPSTREAM=100.115.80.79:7070
```

## Bring-up

```
rsync -av --delete \
  nix/hosts/mandragora-vps/compose/axon/ \
  opc@mandragora-vps:/home/opc/axon/
ssh opc@mandragora-vps 'cd /home/opc/axon && docker compose up -d'
```

## Followups

- `axon.mvr.ac` must be added to `authelia/config/configuration.yml`
  access_control rules (`two_factor`) and authelia restarted, otherwise
  default deny gives 403.
- Hub tile must be present in `hub/static/index.html` and
  `hub/config/services.yaml` for `mandragora-audit 05-hub-tile`.
- Desktop must have:
  - the `axon` binary on PATH (or `~/.local/bin/axon` or
    `/home/m/Projects/axon/build/axon`),
  - `web/dist/index.html` built (cd web && npm run build),
  - the `axon-core` systemd user service enabled and running.
