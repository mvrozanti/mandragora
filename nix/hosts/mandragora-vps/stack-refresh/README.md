# stack-refresh (mandragora-vps)

Nightly image refresh for the VPS stacks, so a vendor's patched image is
running before the trivy scan looks for it. The vuln watch then pages only
what a refresh could not fix.

## What it does

For every stack enrolled in `deploy-stacks.sh` (a stamp in
`/home/opc/.deployed/`), and for each running service with a registry image
and no `build:` section:

1. `docker compose pull` the service; a pull that fails (a local-only tag, an
   unreachable registry) is recorded as skipped.
2. If the pulled image differs from the one the container runs,
   `docker compose up -d --no-build --no-deps` recreates just that service.
3. It waits up to 180 s: healthy, or running 30 s with no restart for a
   service without a healthcheck. An exited, restarting or unhealthy
   container is rolled back to the previous image id and that image is
   held, so the same broken pull is not retried every night; a newer image
   clears the hold.
4. Dangling images are pruned and `refresh-mandragora-vps.json` is written
   beside the scan reports in `/home/opc/vuln/static/`.

Stacks not enrolled (no stamp) and hand-deployed stacks are never touched,
nor anything named in `REFRESH_HOLD` (space-separated `stack` or
`stack/service`, set in the unit). It holds `nb`: SurrealDB can migrate its
data files on a minor upgrade, and rolling the image back does not undo that,
so a database behind a floating tag is upgraded by hand. A dry run puts every
tag it pulled back where it was, so a later deploy does not pick up an image
the refresh never health-checked.

Locally built images (`mandragora/*:local` and other `build:` services) are
not rebuilt here: their findings are mostly Debian packages with no upstream
fix, and a rebuild needs master's build context, which is the deploy path's
job.

Exact-version pins (`seafile-mc:13.0.21`, `open-webui:v0.11.4`,
`caddy-docker-proxy:2.13.1-alpine`) never change on a pull; a fix there is a
pin bump in the compose file. Floating tags (`nginx:stable-alpine`,
`redis:7-alpine`, `forgejo:11`, `*:latest`) pick up rebuilds.

## Paging

The watch `vuln_inventory` source reads `refresh-<host>.json`. A rolled-back
service pages once per failing image (`vuln:refresh`), and a report older than
50 h pages once a day as `vuln:stale`, because a refresh that stopped running
looks exactly like one with nothing to do.

## Pieces

- `refresh.sh` → `/usr/local/bin/stack-refresh.sh` (bin_t, for SELinux).
  `REFRESH_DRY_RUN=1` pulls and reports what would be recreated, recreating
  nothing. Stack names as arguments limit the run.
- `stack-refresh.{service,timer}` → `/etc/systemd/system/`. Daily at
  23:00 UTC plus up to 15 min, ahead of the scan's 00:00–01:00 UTC window,
  as `User=opc`. State and the hold list live in
  `/home/opc/.local/state/stack-refresh/`.
- `install.sh` → pushes the script and units, enables the timer, runs one
  dry run. Idempotent.
