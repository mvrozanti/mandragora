# mandragora-kindle

A jailbroken Kindle Paperwhite 12 (PW6) running as a first-class Mandragora host:
on the tailnet, reachable by name, reproducible from the repo, and monitored
alongside the desktop and the VPS.

Jailbroken 2026-09-12 with **Véra** (firmware 5.19.6, the exact top of Véra's
supported range). The device-level facts, traps and layout live in
[`../nix/hosts/mandragora-kindle/README.md`](../nix/hosts/mandragora-kindle/README.md);
the idea list is in
[`BACKLOG.md`](../nix/hosts/mandragora-kindle/BACKLOG.md) beside it. This page is
the overview: what it is for, how the pieces fit, and how to work on it.

## Intent

A Kindle is an always-on, always-charged, 300 ppi display that costs nothing to
keep showing something. Three things follow from that:

1. **It is a screen the rest of the system can push to.** Art, dashboards,
   whatever — rendered elsewhere, drawn here.
2. **It is a reading device that should be pleasant**, which means KOReader with
   a real launcher rather than Amazon's shelf.
3. **It is a small Linux box on the tailnet**, so it is scriptable like anything
   else here.

The constraint that governs every design decision: **e-ink holds an image at zero
power.** Cost is refreshes and radio, never CPU or "being on". A portrait that
changes hourly is close to free; a clock that ticks every second would ruin the
battery. Design everything to **wake rarely, draw once, sleep**.

## Layout

```
mandragora-desktop                     mandragora-vps                  kindle
──────────────────                     ──────────────                  ──────
~/Pictures/wllpps  ──kindle-art──▶                          ──▶  /mnt/us/mandragora/art/
nix/hosts/mandragora-kindle/                                          bin/  rc/  state/  log/
        │          ──kindle-push─▶                          ──▶  scriptlets/ · icons/
        │                                                          /mnt/us/documents/*.sh
        │                                                          koreader/plugins/mandragora.koplugin/
        │                                                          /etc/upstart/mandragora.conf
        │
 VictoriaMetrics ──scrape 5m──▶ kindle.mvr.ac/metrics ──ssh──▶  (battery, services, storage)
 Grafana "Mandragora Kindle"
                                kindle.mvr.ac (panel) ──ssh──▶  /dev/fb0, fbink, documents
```

Three surfaces, three owners:

| where | what | in the repo |
|---|---|---|
| **device** | boot job, daemons, scriptlets, KOReader plugin | `nix/hosts/mandragora-kindle/` |
| **VPS** | `kindle.mvr.ac` — panel, screen mirror, metrics | `nix/hosts/mandragora-vps/compose/kindle/` |
| **desktop** | `kindle-push`, `kindle-art`, scrape job, dashboard | `.local/bin/`, `nix/modules/core/monitoring-*.nix` |

## Workflow

```sh
kindle-push          # payload → device: rc, scriptlets, plugin, boot job, restart services
kindle-art           # $WALLPAPER_DIR → e-ink greyscale → device (incremental)
kindle-art --reset   # after changing conversion settings
ssh root@kindle      # tailnet, by name
```

`kindle-push` is idempotent and is the only way things should reach the device —
if something is on the Kindle but not in `nix/hosts/mandragora-kindle/`, it will
be lost on the next wipe and it is a bug. The device is meant to be reproducible:
jailbreak, then one command.

Editing the KOReader plugin means a **KOReader restart** to reload it; editing a
scriptlet does not. Editing `rc/start.sh` needs `kindle-push` and either a reboot
or re-running `start.sh` by hand.

### Access

Two independent paths, deliberately:

- **Tailscale SSH** — `ssh root@kindle`, works from anywhere, no port, no key.
- **dropbear on 2223** — key-only, LAN fallback for when tailscaled is the thing
  that is broken.

KOReader's own SSH server (port 2222) was the bootstrap and is no longer needed;
it is the only passwordless-capable thing on the device and should stay off.

## Monitoring, and the switch

`kindle.mvr.ac/metrics` is scraped by VictoriaMetrics every **5 minutes** and
drawn by the Grafana dashboard `mandragora-kindle`. Every scrape is an SSH round
trip to a battery device, so:

- `/metrics` is served **without Authelia but only to the tailnet** — Prometheus
  cannot log in — via a Caddy path matcher with a `not remote_ip 100.64.0.0/10`
  403 guard. Everything else on the host stays gated.
- the app caches each sample for 4 minutes, so a stray `curl` cannot multiply the
  real polling rate;
- and there is a **pause button on the panel**. Paused, `/metrics` still emits
  `kindle_monitor_enabled 0` so the Grafana tile reads *paused* rather than going
  blank and looking like an outage. The flag persists across restarts.

## Apps

The delivery tiers, cheapest first — always use the cheapest that works:

1. **Scriptlet** — a `.sh` in `/mnt/us/documents` with a `# Name:` header becomes a
   library tile. No daemon, no memory when idle.
2. **KOReader plugin** — Lua, in-process, surfaced as a SimpleUI quick action
   through its public `QA.register{ id, label, icon, execute }` API. This is where
   anything needing touch input or persistent drawing belongs, because KOReader
   owns the framebuffer and the touchscreen.
3. **Native armhf binary** — FBInk or a GTK window registered into the stock
   Awesome WM. Built with KindleModding's `koxtoolchain` + `kindle-sdk`, target
   `kindlehf`. Nothing needs this yet.

**Portrait** started as tier 1 and moved to tier 2 for exactly the reason the tiers
exist: an FBInk scriptlet draws once and exits, so it cannot take a tap and
KOReader repaints over it. As a Lua widget it owns the screen properly and handles
tap-to-shuffle.

## Reading order for someone new

1. [`../nix/hosts/mandragora-kindle/README.md`](../nix/hosts/mandragora-kindle/README.md)
   — device facts and the traps. Read before touching anything on the device.
2. [`../nix/hosts/mandragora-vps/compose/kindle/README.md`](../nix/hosts/mandragora-vps/compose/kindle/README.md)
   — the panel, the screen mirror, the metrics gate.
3. [`BACKLOG.md`](../nix/hosts/mandragora-kindle/BACKLOG.md) — what is next and why.
