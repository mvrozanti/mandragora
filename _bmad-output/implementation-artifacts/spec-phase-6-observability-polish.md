---
title: 'Phase 6 — Observability & Polish'
type: 'feature'
created: '2026-04-18'
status: 'done'
baseline_commit: '03f469525fcbaa7f1dad4bdfaa0c92b382db3378'
context:
  - atlas/non-negotiables.md
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Mandragora has no system health awareness — SMART failures, disk pressure, service crashes, and network anomalies are invisible until they cause pain. Seafile sync to the arch-slave is also unplanned, leaving backup unresolved.

**Approach:** (1) Move the existing `strays.sh` to `snippets/` (non-negotiable compliance), add a `health-check.sh` audit script, and wire both into a NixOS module with two systemd timers — a rapid watch (every 30 min) and a daily digest. Mandragora-only. (2) Scaffold a Seafile client NixOS module (`enable = false`) ready to activate once the arch-slave exists.

## Boundaries & Constraints

**Always:**
- Audit module imported only in `mandragora-desktop`, never `shadow-desktop`
- All shell scripts in `snippets/` (non-negotiable) — move existing `strays.sh` accordingly
- Audit logs persist: written to `/persistent/logs/strays/`
- Seafile ships with `enable = false`; no server credentials hardcoded
- sops-nix for any Seafile credentials when activated

**Ask First:**
- Seafile server address, port, and library IDs (unknown until arch-slave is set up)

**Never:**
- Import audit or Seafile modules in `shadow-desktop`
- Plain-text credentials in git

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Watch timer fires (30 min) | Live system | Critical findings logged to journal + `/persistent/logs/strays/watch-YYYY-MM-DD.log` | Non-zero exit captured; unit marked failed; visible via `journalctl` |
| Digest timer fires (daily 06:00) | Live system | Full report appended to `/persistent/logs/strays/digest-YYYY-MM-DD.log` | Same as above |
| `strays find` | Running system | List of non-persistent paths in `/etc`, `/var`, `$HOME` | Exits 1 on permission error |
| `strays adopt <path>` | File path | File moved to `/persistent`, bind-mounted back | Exits 1 if already persistent or path missing |
| Seafile `enable = false` | Any boot | No Seafile process started; no secrets required | — |

</frozen-after-approval>

## Code Map

- `snippets/strays.sh` — MOVED from `modules/audits/strays.sh`; impermanence management tool (find/adopt/delete)
- `snippets/health-check.sh` — NEW: system health audit (disk usage, SMART, failed units, listening ports, thermals, memory, Btrfs scrub age)
- `modules/audits/default.nix` — NEW: wires both scripts; creates `strays` CLI via `pkgs.substituteAll`; defines watch + digest timers; creates log dir
- `hosts/mandragora-desktop/default.nix` — ADD import of `modules/audits/default.nix`
- `modules/desktop/seafile.nix` — NEW: Seafile client scaffold (`enable = false`; sops secret placeholder; TODO server config)
- `hosts/mandragora-desktop/default.nix` — ADD import of `modules/desktop/seafile.nix`
- `modules/core/secrets.nix` — ADD commented-out `seafile/auth-token` secret (activate when server exists)

## Tasks & Acceptance

**Execution:**
- [x] `snippets/strays.sh` -- moved from `modules/audits/strays.sh`; placeholders preserved
- [x] `snippets/health-check.sh` -- created: disk usage, SMART, failed units, listening ports, thermals, memory, Btrfs scrub; WARN/INFO/OK tagged; exits 1 on any WARN; @DISK_WARN_THRESHOLD@ and @LOG_FILE@ substitution placeholders
- [x] `modules/audits/default.nix` -- created: substituteAll for both scripts; strayscli via writeShellApplication; audit-watch timer (30 min) + audit-digest timer (daily 06:00); tmpfiles rule for /persistent/logs/strays/
- [x] `hosts/mandragora-desktop/default.nix` -- added modules/audits/default.nix + modules/desktop/seafile.nix imports
- [x] `modules/desktop/seafile.nix` -- created: mkEnableOption (false); seafile-client package; systemd.user.services.seafile-daemon; TODO comments for server URL, library IDs, sops wiring
- [x] `modules/core/secrets.nix` -- added commented-out seafile/auth-token secret block

**Acceptance Criteria:**
- Given mandragora-desktop config, when `nix build .#nixosConfigurations.mandragora-desktop.config.system.build.toplevel`, then build succeeds
- Given shadow-desktop config, when built, then no audit or seafile units present
- Given the built system, when `which strays`, then the command resolves to the nix store path
- Given audit-watch.timer, when `systemctl list-timers`, then it appears with a 30-min interval
- Given `services.mandragora-seafile.enable = false`, when booting, then no `seaf-cli` process starts

## Spec Change Log

## Design Notes

**Two-timer design:** `audit-watch` runs only the fast/critical checks (disk full, SMART errors, failed units) every 30 min — cheap and actionable. `audit-digest` runs everything including slow checks (Btrfs scrub age, port baseline diff) once daily. Both services use `StandardOutput=append:/persistent/logs/strays/...` so logs accumulate across reboots.

**strays.sh substitution:** `pkgs.substituteAll` replaces `@VAULT@` → `/persistent` and `@USER_HOME@` → `/home/m` at build time. The result is wrapped via `pkgs.writeShellApplication` to get a proper derivation with a `bin/strays` entry point accessible system-wide.

**Seafile scaffold pattern:** The module defines a NixOS option `services.mandragora-seafile.enable` (false by default) so it can be activated with a single line when the server exists. Credentials flow through sops-nix once added to `secrets.yaml`. Library sync paths are left as explicit TODO comments.

## Verification

**Commands:**
- `nix build .#nixosConfigurations.mandragora-desktop.config.system.build.toplevel` -- expected: exit 0
- `nix build .#nixosConfigurations.shadow-desktop.config.system.build.toplevel` -- expected: exit 0, no audit/seafile units
- `nix flake check` -- expected: no evaluation errors

## Suggested Review Order

**Entry point — system wiring**

- Both new modules added here; confirms audit+seafile scope to Mandragora only
  [`default.nix:4`](../../hosts/mandragora-desktop/default.nix#L4)

**Audit system**

- IFD-safe strays CLI wiring + two timer definitions; core architectural decision
  [`default.nix:1`](../../modules/audits/default.nix#L1)

- Health script: disk/SMART/units/ports/thermals/memory/btrfs; all probe logic here
  [`health-check.sh:1`](../../snippets/health-check.sh#L1)

- Impermanence management tool (moved from modules/audits/ — non-negotiable fix)
  [`strays.sh:1`](../../snippets/strays.sh#L1)

**Seafile scaffold**

- Option definition + forking service with PIDFile + restart limits; enable=false guard
  [`seafile.nix:1`](../../modules/desktop/seafile.nix#L1)

**Secrets placeholder**

- Commented-out seafile/auth-token secret; activate alongside seafile.enable
  [`secrets.nix:17`](../../modules/core/secrets.nix#L17)
