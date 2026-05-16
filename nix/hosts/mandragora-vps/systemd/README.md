# `mandragora-vps` host systemd units

Snapshot of systemd units that live in `/etc/systemd/system/` on the
VPS host (Oracle Linux, not NixOS). The repo holds the canonical
text; the VPS-side files are kept in sync by hand until a pull-from-
git workflow lands.

## Units tracked

| Path | Purpose | Enable on VPS |
|---|---|---|
| `socat-tailnet@.service` | Template — listen on `0.0.0.0:%i` and forward to `100.115.80.79:%i` (mandragora desktop tailnet IP). One instance per port (`%i` is the port). | `systemctl enable --now socat-tailnet@7681.service` for ttyd; one per hub service that lives on the desktop. |

## Why a template

Adding a new desktop-backed hub service (slither, future…) is a
single command: `systemctl enable --now socat-tailnet@<port>.service`.
No new unit file. The Caddy label on the homepage container points
at `host.docker.internal:<port>`; the socat instance routes the rest.

## Why bind 0.0.0.0 not 127.0.0.1

The VPS Caddy runs in a Docker bridge container (`seafile-net`), so it
cannot reach the host's loopback. With `extra_hosts:
["host.docker.internal:host-gateway"]` the container resolves
`host.docker.internal` to the bridge gateway IP. socat must listen on
that IP — easiest is `0.0.0.0`.

The exposed port is **not** publicly reachable: Oracle Cloud's
default network security list only allows 22 / 80 / 443 inbound,
so an unprivileged 0.0.0.0 listener on any other port is reachable
only from the VPS itself. Adding a Caddy `not remote_ip 100.64.0.0/10`
gate on the public-facing vhost is defense-in-depth in case Oracle's
NSG is ever loosened.

## Deploy

```
sudo install -m 0644 socat-tailnet@.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now socat-tailnet@7681.service
```

Currently enabled instances (one per desktop-backed hub vhost):

| Port | Vhost | Desktop service |
|---|---|---|
| `7681` | `term.mvr.ac` | ttyd |
| `8088` | `slither.mvr.ac` | slither-io |
| `3000` | `grafana.mvr.ac` | grafana |
| `6680` | `mpd.mvr.ac` | mympd |
| `6681` | `rgb.mvr.ac` | rgb-control |
| `6682` | `gen.mvr.ac` | im-gen-web |
| `6683` | `llama.mvr.ac` | open-webui |
| `7682` | `claude.mvr.ac` | claude-web (aiohttp dir picker that spawns detached `tmux + claude`; no in-browser shell) |
| `6684` | `hub.mvr.ac` `/api/gpu*` | gpu-status (JSON snapshot: gpu_lock holder + nvidia-smi) |
