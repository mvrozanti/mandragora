# `meme.mvr.ac` — runner UI for `meme` image tagger

Authelia-gated reverse proxy for the desktop-side `meme-server` user service.
Caddy on the docker-proxy terminates TLS and forward-auths every request
through Authelia, then proxies to the desktop over the tailnet at
`${MEME_UPSTREAM:-100.115.80.79:8093}`.

## Upstream

- Desktop user service: `systemctl --user status meme-web`
- Port: `8093` (opened only on `tailscale0`)
- Source: `nix/modules/services/meme-web.nix` + `nix/pkgs/meme-cli.nix`
  (`meme-server` wrapper around `server.py` from
  `github.com/mvrozanti/vtag`).

## First-time bring-up on the VPS

```sh
ssh opc@mandragora-vps
sudo mkdir -p /home/opc/meme
sudo chown -R opc:opc /home/opc/meme
exit

rsync -a /persistent/mandragora/nix/hosts/mandragora-vps/compose/meme/ \
  opc@mandragora-vps:/home/opc/meme/

ssh opc@mandragora-vps 'cd /home/opc/meme && docker compose up -d'
```

`seafile-net` must already exist (it does, from the Seafile stack).

## Updating

Compose-only edits: re-`rsync` and `docker compose up -d` (no
`mandragora-switch` required). Changes to the upstream server live in the
`meme-web` nixos module and ship via `mandragora-switch` on the desktop.

## Override upstream

If the desktop's tailscale IP ever changes, set `MEME_UPSTREAM` in the
compose env (or alongside `MVR_AC` in the docker-proxy environment) to
`<ip>:8093`. The default `100.115.80.79:8093` matches the current
desktop.
