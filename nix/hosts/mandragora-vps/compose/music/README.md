# `music.mvr.ac` — emotion-tagging explorer

Authelia-gated reverse proxy for the desktop-side `emotion-web` user
service. Caddy on the docker-proxy terminates TLS and forward-auths every
request through Authelia, then proxies to the desktop over the tailnet
at `${MUSIC_UPSTREAM:-100.115.80.79:8094}`.

## Upstream

- Desktop user service: `systemctl --user status emotion-web`
- Port: `8094` (opened only on `tailscale0`)
- Source: `nix/modules/services/emotion-web.nix` + `nix/pkgs/emotion-web.nix`
  + `.local/share/emotion-web/{server.py,static/index.html}`

The desktop service serves both the UI and a thin JSON API at
`/api/{status,songs,song/<name>,jobs,jobs/<id>,tag}`. The tag endpoint
queues a job that runs `gpu-lock run -- uv run rank.py …` under
`~/Music/.emotion/`, which already holds the CLAP + Essentia + ollama
pipeline.

## First-time bring-up on the VPS

```sh
ssh opc@mandragora-vps
sudo mkdir -p /home/opc/music
sudo chown -R opc:opc /home/opc/music
exit

rsync -a /etc/nixos/mandragora/nix/hosts/mandragora-vps/compose/music/ \
  opc@mandragora-vps:/home/opc/music/

ssh opc@mandragora-vps 'cd /home/opc/music && docker compose up -d'
```

## Updating

Compose-only edits: re-`rsync` and `docker compose up -d`. Changes to
the upstream UI/server live in the `emotion-web` package and ship via
`mandragora-switch` on the desktop.

## Override upstream

If the desktop tailscale IP ever changes, set `MUSIC_UPSTREAM` in the
compose env to `<ip>:8094`. The default `100.115.80.79:8094` matches the
current desktop.
