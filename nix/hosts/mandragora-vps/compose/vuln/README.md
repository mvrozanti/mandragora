# vuln.mvr.ac — CVE dashboard

Static dashboard rendering the desktop's `vulnix --system` scan of the
current NixOS closure. Auth-gated (authelia two_factor), tiled on the
hub as `sec / vuln`.

## Pieces

- `docker-compose.yml` — nginx serving `static/`, behind
  `forward_auth` to authelia (mirrors the `logs` stack).
- `static/{index.html,app.js,style.css}` — client-side dashboard.
  Fetches `report.json`, buckets by CVSS (critical ≥9 / high 7–9 /
  medium 4–7 / low <4), and applies the name-collision noise filter
  ported from `~/.ai-shared/rules/cve-scan.md` (toggle to reveal).
- `static/report.json` — **gitignored**, written by `vuln-publish`.

## Data flow

1. Desktop weekly timer runs `cve-scan.service` → `vulnix --system
   --json` → `~/.local/state/cve-scan/latest.json`.
2. `cve-scan.sh` then calls `vuln-publish` (best-effort), which slims
   the report (jq) and `rsync`s it to
   `opc@…:/home/opc/vuln/static/report.json`.
3. nginx serves it immediately — no container restart.

Run `vuln-publish` by hand any time to push the latest scan.

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
