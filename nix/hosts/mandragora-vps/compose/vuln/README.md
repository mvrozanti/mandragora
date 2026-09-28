# vuln.mvr.ac — multi-host CVE dashboard

Static dashboard rendering every mandragora host's CVE scan: `vulnix
--system` over the NixOS closure on desktop/wsl, trivy over running
container images on the VPS (`../../vuln-scan/`). Auth-gated (authelia
two_factor), tiled on the hub as `sec / vuln`.

Each host self-scans on a daily timer and publishes its own
`report-<hostname>.json`; the dashboard aggregates them with per-host
tabs and an "all hosts" merged view (one row per package, badged with
the hosts it affects).

## Pieces

- `docker-compose.yml` — nginx serving `static/`, behind
  `forward_auth` to authelia (mirrors the `logs` stack).
- `static/{index.html,app.js,style.css}` — client-side dashboard.
  Fetches `hosts.json` then each `report-<host>.json`, buckets by CVSS
  (critical ≥9 / high 7–9 / medium 4–7 / low <4), and applies the
  noise filter from `static/noise.json` (toggle to reveal). Falls back to a
  single legacy `report.json` if no manifest is present.
- `static/noise.json` — the **one** false-positive list. Read by this
  dashboard, the waybar security menu (`nix/snippets/security-menu.py`),
  the watch `vuln_inventory` source, and the `cve-scan` agent rule.
  Add false positives here, never inline in a consumer.
- `static/report-*.json`, `static/hosts.json` — **gitignored**,
  written by `vuln-publish` (desktop/wsl) and `vuln-scan-vps` (VPS).

The scanner/publisher live in the desktop+wsl closures via
`nix/modules/core/vuln-scan.nix` (imported by both hosts). The VPS is
Oracle Linux, not a Nix closure; its running images are scanned by
trivy (`nix/hosts/mandragora-vps/vuln-scan/`).

## Report schema v2

```
{ schema: 2, scanner: "vulnix"|"trivy", generated: "<ISO-8601 UTC>", host,
  error?: "<why the last scan failed; entries are the previous scan's>",
  entries: [{ pname, version, max, ecosystem, images?[],
              cves: [{ id, score, desc, severity?, fixed?, fixed_version? }] }] }
```

`images`, `severity`, `fixed`, `fixed_version` come from trivy only.
Additive over v1, so older readers keep working.

## Exposure maps

`exposure-<host>.json` sits beside each report and says which affected
packages are actually listening:

```
{ schema: 1, host, generated, listeners: [{ port, proto, scope, process,
  bind?, packages?: [{pname, version}], image?, vhost? }] }
```

- **desktop/wsl**: root `vuln-exposure.service` (hourly timer,
  `.local/bin/vuln-exposure.py`) reads `ss -tlnp`, classifies each
  listener against the evaluated NixOS firewall — `open` (allowed on
  every interface, so global IPv6 too), `lan` (enp only), `tailnet`
  (tailscale0 only); loopback and firewalled sockets are dropped — and
  maps the process through `/proc/<pid>/{exe,maps,cmdline}` to the Nix
  store packages it runs. `vuln-publish` ships it with the report.
- **VPS**: `scan.sh` records host-published ports (`public`) and
  caddy-labelled containers (`public`, or `authed` behind
  `forward_auth`), keyed by image.

Matching is by exact (pname, version) or image, so a service linking
openssl 3.6.1 does not mark an old 3.0.19 as exposed. The dashboard
shows a `listening` badge; watch tags `vuln:exposed` for
open/lan/public and `vuln:reachable` for tailnet/authed.

## Responsibility split

This stack owns **current state**: what is affected right now, per host.
It never notifies. **News** — a new (package, CVE) pair, a CVE newly on
CISA KEV, a scanner gone stale — is the watch stack's `vuln_inventory`
source, which reads these same files over `seafile-net`
(`http://vuln/…`) and pushes through Telegram. Scanners own the
"is this version affected" decision; nothing downstream re-matches
versions. A fix is confirmed when the next scan stops listing it, which
shows here; watch stays quiet about resolutions.

## Data flow (per host)

1. Daily `cve-scan.service` runs `vulnix --system --json` →
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
