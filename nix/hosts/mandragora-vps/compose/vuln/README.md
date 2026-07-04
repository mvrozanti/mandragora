# vuln.mvr.ac — multi-host CVE dashboard

Static dashboard rendering every mandragora NixOS host's `vulnix
--system` scan of its current closure. Auth-gated (authelia
two_factor), tiled on the hub as `sec / vuln`.

Each host self-scans on a weekly timer and publishes its own
`report-<hostname>.json`; the dashboard aggregates them with per-host
tabs and an "all hosts" merged view (one row per package, badged with
the hosts it affects).

## Pieces

- `docker-compose.yml` — nginx serving `static/`, behind
  `forward_auth` to authelia (mirrors the `logs` stack).
- `static/{index.html,app.js,style.css}` — client-side dashboard.
  Fetches `hosts.json` then each `report-<host>.json`, buckets by CVSS
  (critical ≥9 / high 7–9 / medium 4–7 / low <4), and applies the
  name-collision noise filter ported from
  `~/.ai-shared/rules/cve-scan.md` (toggle to reveal). Falls back to a
  single legacy `report.json` if no manifest is present.
- `static/report-*.json`, `static/hosts.json` — **gitignored**,
  written by `vuln-publish` from each host.

The scanner/publisher live in the desktop+wsl closures via
`nix/modules/core/vuln-scan.nix` (imported by both hosts). The VPS is
Oracle Linux, not a Nix closure — `vulnix` does not apply there; its
container images would need a separate image scanner (trivy/grype).

## Data flow (per host)

1. Weekly `cve-scan.service` runs `vulnix --system --json` →
   `~/.local/state/cve-scan/latest.json`.
2. `cve-scan.sh` then calls `vuln-publish` (best-effort), which slims
   the report (jq) and `rsync`s it to
   `opc@…:/home/opc/vuln/static/report-<hostname>.json`, then
   regenerates `hosts.json` from the directory listing.
3. nginx serves it immediately — no container restart.

Run `vuln-publish` by hand on any host to push its latest scan. Each
host needs SSH reach to the VPS (tailscale + authorized key).

## Deploy

```bash
# first-time slot provisioning on the VPS
ssh opc@100.84.78.83 'sudo mkdir -p /home/opc/vuln/static && sudo chown -R opc:opc /home/opc/vuln'
# push static site + latest report
./deploy.sh
# bring the container up
ssh opc@100.84.78.83 'cd /home/opc/vuln && docker compose up -d'
```

The compose file must also be present on the VPS
(`/home/opc/vuln/docker-compose.yml`) — `rsync` it alongside the first
deploy.
