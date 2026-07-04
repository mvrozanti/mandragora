# food.mvr.ac

Mobile shopping list for the cooking vault. Add foods on your phone — tap from
your known catalog (name, shelf-life, healthiness, last price) or type anything
free-form. Behind Authelia; the active list persists server-side and syncs
across devices.

## Architecture

- `app/server.py` — zero-dependency Python stdlib server. Serves the static
  SPA, `GET /catalog.json` (read from the data volume), `GET /api/list`,
  `PUT /api/list` (persists to `/data/list.json`), `GET /healthz`.
- `app/public/` — the mobile SPA only. **No food data lives in this repo.**
- The food catalog (`catalog.json`) is generated in the private cooking vault
  and lives only on the VPS at `/home/opc/food/data/catalog.json`
  (git-excluded, the same way `demo`'s vault data lives only on the VPS). The
  server reads it from there.
- App-authoritative: the active list lives on the VPS data volume; nothing
  writes back into git.

## Deploy

```sh
./deploy.sh
```

rsyncs the stack to `/home/opc/food/` on the VPS and runs
`docker compose up -d --build`. `seafile-net` must already exist. `data/` and
`.env` are never overwritten.

## Refresh the catalog

The catalog is not in this repo. Regenerate it in the cooking vault, then push
it to the VPS data volume (no rebuild needed):

```sh
rsync ~/Projects/cooking/catalog.json opc@mandragora-vps:/home/opc/food/data/catalog.json
```

## Auth

Gated by Authelia (two-factor) via the Caddy `forward_auth` labels. Add
`food.mvr.ac` to the `access_control` two-factor domain list in
`../authelia/config/configuration.yml`.
