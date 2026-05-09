# `microbin/` — tailnet-only paste service

Stack for `paste.mvrozanti.duckdns.org`. Lightweight Rust paste server
(microbin), gated to the tailnet via a Caddy `not remote_ip 100.64.0.0/10`
matcher returning 403 for non-tailnet sources.

## Container

| Container | Image | Port | Persistence |
|---|---|---|---|
| `microbin` | `ghcr.io/szabodanika/microbin:2.0.4` | `8080` (in-container) | bind mount `./data` → `/app/pasta_data` |

Since microbin runs on the VPS in `seafile-net`, the VPS-side caddy
reaches it directly by container service name — no `socat` shim is
needed (unlike ttyd, which lives on the desktop and is proxied via
`socat-tailnet@7681.service` + `host.docker.internal`).

## Live location

`/home/opc/microbin/`

```
cd /home/opc/microbin && sudo docker compose up -d
```

## Env

`.env` (root-owned, gitignored) holds:
- `MICROBIN_AUTH_USERNAME`
- `MICROBIN_AUTH_PASSWORD`
- `PASTE_HOSTNAME`  (default: `paste.mvrozanti.duckdns.org`)
- optional `MICROBIN_IMAGE`, `MICROBIN_DATA_VOLUME`

Pastes that are visible to anyone with the paste URL **on the
tailnet**; the `--no-listing` setting hides the index page so the
URLs aren't enumerable. Combined with the Caddy IP gate, public
internet sees only the 403.

## Verification

- `curl -sI https://paste.mvrozanti.duckdns.org/` (from public): `403`
- From a tailnet client: `200` and serves the paste UI.
- `curl -X POST -u m:$PASS https://paste.mvrozanti.duckdns.org/upload -F 'content=hello'` (from tailnet): paste URL response.
