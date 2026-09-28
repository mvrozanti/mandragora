# vuln-scan (mandragora-vps)

Trivy-based CVE scanner for the VPS — the non-NixOS counterpart to the
desktop/wsl `cve-scan`. Oracle Linux + docker stacks can't be scanned by
`vulnix` (no Nix closure), so this scans every **running container image**
with [trivy](https://trivy.dev) and writes a `report-mandragora-vps.json`
in the same schema the `vuln.mvr.ac` dashboard consumes.

## Pieces

- `scan.sh` → installed at `/usr/local/bin/vuln-scan-vps.sh` (bin_t, so
  SELinux lets systemd exec it — files under /home are denied). Runs
  trivy (dockerized, DB cached in the `trivy-cache` volume) over
  `docker ps` images, normalizes to report schema v2
  (`{schema, scanner, generated, host, entries[]}`; each entry carries
  `pname, version, ecosystem, images[], max, cves[]`, each CVE
  `id, score, severity, desc, fixed, fixed_version`), merges duplicates
  across images (key: pname + version + ecosystem), writes the report
  into the served static dir, and regenerates `hosts.json`. If trivy
  fails on every image the previous entries are kept and the report
  gains an `error` field, so the watch `vuln_inventory` source can
  raise a stale-scanner alert instead of the report silently freezing.
- `vuln-scan-vps.{service,timer}` → `/etc/systemd/system/`. Daily
  oneshot as `User=opc` (opc is in the docker group).
- `install.sh` → pushes the script + units, enables the timer, runs
  one scan. Idempotent.

## Deploy

```bash
./install.sh          # from this dir, on the desktop
```

Runs entirely over `ssh opc@100.84.78.83`. The units need `sudo` to land
in `/etc/systemd/system`; everything else is opc-owned.

## Manual run / debug

```bash
ssh opc@100.84.78.83 'sudo systemctl start vuln-scan-vps.service'
ssh opc@100.84.78.83 'journalctl -u vuln-scan-vps.service -f'
```

## Notes

- Scans **running** images only (the live attack surface). Stopped or
  merely-pulled images are ignored.
- CVSS score preference: `CVSS.nvd.V3Score`, else `CVSS.redhat.V3Score`,
  else 0 (shown as unscored); trivy's vendor `severity` is kept for
  those unscored rows.
- Host OS RPMs are **not** scanned yet — add a `trivy rootfs /` pass if
  the Oracle base packages become a concern.
