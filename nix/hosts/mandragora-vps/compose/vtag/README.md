# `vtag.mvr.ac` — runner UI for `vtag` image tagger

Authelia-gated reverse proxy for the desktop-side `vtag-server` user service.
Caddy on the docker-proxy terminates TLS and forward-auths every request
through Authelia, then proxies to the desktop over the tailnet at
`${VTAG_UPSTREAM:-100.115.80.79:8093}`.

## Upstream

- Desktop user service: `systemctl --user status vtag-web`
- Port: `8093` (opened only on `tailscale0`)
- Source: `nix/modules/services/vtag-web.nix` + `nix/pkgs/vtag-cli.nix`
  (`vtag-server` wrapper around `server.py` from
  `github.com/mvrozanti/vtag`).

## First-time bring-up on the VPS

```sh
ssh opc@mandragora-vps
sudo mkdir -p /home/opc/vtag
sudo chown -R opc:opc /home/opc/vtag
exit

rsync -a /persistent/mandragora/nix/hosts/mandragora-vps/compose/vtag/ \
  opc@mandragora-vps:/home/opc/vtag/

ssh opc@mandragora-vps 'cd /home/opc/vtag && docker compose up -d'
```

`seafile-net` must already exist (it does, from the Seafile stack).

## Updating

Compose-only edits: re-`rsync` and `docker compose up -d` (no
`mandragora-switch` required). Changes to the upstream server live in the
`vtag-web` nixos module and ship via `mandragora-switch` on the desktop.

## Override upstream

If the desktop's tailscale IP ever changes, set `VTAG_UPSTREAM` in the
compose env (or alongside `MVR_AC` in the docker-proxy environment) to
`<ip>:8093`. The default `100.115.80.79:8093` matches the current
desktop.
