# food.mvr.ac

Mobile shopping list for the cooking vault. Add foods on your phone — tap from
your known catalog (name, shelf-life, healthiness, last price) or type anything
free-form. Behind Authelia; the active list persists server-side and syncs
across devices.

## Architecture

- `app/server.py` — zero-dependency Python stdlib server. Serves the static
  SPA, `GET /catalog.json` (read from the data volume), `GET /api/list`,
  `PUT /api/list` (persists to `/data/list.json`), the capture inbox
  (`GET`/`POST`/`PUT /api/inbox`, persists to `/data/inbox.json`), and
  `GET /healthz`.
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

## Capture inbox (new foods, no LLM)

Typing a food the catalog doesn't know adds it to the shopping list **and**
appends it to a durable capture queue at `/data/inbox.json` — no Claude, no
tokens. Removing it from the list does not remove it from the inbox, so a
capture is never lost. Entries are `{name, note}`, deduped by
accent-folded name.

Later, an agent drains the queue in one batched pass — reads all pending
names, turns each into a full vault note (schema, perspectives, `catalog.json`),
then clears the inbox by writing `{"items": [], "updated": null}` back via
`PUT /api/inbox`. Read the pending queue any time with:

```sh
ssh opc@mandragora-vps 'docker exec food wget -qO- http://127.0.0.1:8080/api/inbox'
```

## Auth

Gated by Authelia (two-factor) via the Caddy `forward_auth` labels. Add
`food.mvr.ac` to the `access_control` two-factor domain list in
`../authelia/config/configuration.yml`.
