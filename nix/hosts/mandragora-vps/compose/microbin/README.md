# `microbin/` — paste service (Authelia-gated)

Stack for `paste.mvr.ac`. Lightweight Rust paste server (microbin).

## Container

| Container | Image | Port | Persistence |
|---|---|---|---|
| `microbin` | `danielszabo99/microbin:latest` | `8080` (in-container) | bind mount `./data` → `/app/pasta_data` |

Since microbin runs on the VPS in `seafile-net`, the VPS-side caddy
reaches it directly by container service name — no `socat` shim is
needed (unlike ttyd / slither / mympd / rgb-control / im-gen-web,
which live on the desktop and are proxied via the
`socat-tailnet@<port>.service` family + `host.docker.internal`).

## Auth

Single-factor Authelia (password + TOTP) via Caddy `forward_auth`.
microbin's native basic auth (`MICROBIN_AUTH_USERNAME` /
`MICROBIN_AUTH_PASSWORD` env vars) is **off** — Authelia is the
only gate; a second prompt would be redundant friction. The
`MICROBIN_NO_LISTING=true` setting still hides the index page so
paste URLs aren't enumerable by anyone who somehow lands past
Authelia.

Previous state (pre-Phase F) used a tailnet IP gate + microbin
native auth instead — dropped in favor of "everything through
Authelia" so pastes are reachable from any network with valid TOTP.

## Live location

`/home/opc/microbin/`

```
cd /home/opc/microbin && sudo docker compose up -d
```

## Env

`.env` (root-owned, gitignored) holds:
- `MVR_AC` (default: `mvr.ac`)
- optional `MICROBIN_IMAGE`, `MICROBIN_DATA_VOLUME`, `PASTE_HOSTNAME`

## Verification

- `curl -sI https://paste.mvr.ac/` (from anywhere): `302 → auth.mvr.ac/?rd=…`
- After Authelia auth: `200` and serves the paste UI.
- From the auth-bypassed seafile-net inside the container:
  `curl -sI http://localhost:8080/` (via `docker exec`): `200`.
