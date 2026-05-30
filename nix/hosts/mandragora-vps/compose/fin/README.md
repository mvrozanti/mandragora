# fin · live view of orderbook-algotrading

Public read-only dashboard for the orderbook-algotrading paper-trade
state. Serves at https://fin.mvr.ac (no auth — paper-trade data is
non-sensitive, OSS-bound).

Read-only guarantees: only GET routes, SQLite opened mode=ro, mount
volumes :ro. Three layers of read-only enforcement (see "Read-only
guarantees" below).

## Source

Container is built from `~/Projects/orderbook-algotrading/webui/`.
Build on desktop, transfer image to VPS, run.

```bash
# Desktop
cd ~/Projects/orderbook-algotrading
docker build -f webui/Dockerfile -t fin-mvr-ac:latest .
docker save fin-mvr-ac:latest | ssh opc@mandragora-vps "docker load"

# VPS
ssh opc@mandragora-vps "cd /home/opc/fin && docker compose up -d"
```

## Mounts

`${FIN_DATA_DIR}` (default `/home/opc/dnl_paper`) mounted read-only at
`/data`. The directory holds:

```
algorithms/delta_neutral_lp/live/paper_ledger.sqlite
algorithms/glp_delta_neutral/live/paper_ledger.sqlite
algorithms/lsd_discount_harvester/live/paper_ledger.sqlite
algorithms/lsd_discount_harvester_frxeth/live/paper_ledger.sqlite  (post-frxETH deploy)
algorithms/*/live/snapshots/*.jsonl
algorithms/delta_neutral_lp/live/gate_latest.json
STATE.md
```

All populated by the existing hourly crons. No new cron entries needed
for the web UI itself — it reads what's already there.

## Routing

Caddy label `https://fin.mvr.ac` via the `seafile-net` docker-proxy.
Forward-auth via `authelia:9091` (same pattern as kl, microbin).

No DNS changes — `*.mvr.ac` wildcard already routes here.

## Hub tile

Per AGENTS.md §16 ("Every *.mvr.ac subdomain needs a hub tile") this
stack ships with a matching tile addition in
`compose/hub/static/index.html` in the same branch.

## Read-only guarantees

`webui/app.py` exposes only GET routes. SQLite is opened with
`mode=ro` via URI. The container mount is `:ro`. Three independent
layers of read-only enforcement.

## Disable / rollback

```bash
ssh opc@mandragora-vps "cd /home/opc/fin && docker compose down"
```

Removing the caddy label from compose + `up -d` is enough — caddy
auto-reconfigures. Removing the hub tile is a separate one-line edit.
