# `music.mvr.ac` — song analyzer + emotion explorer

Merged static + proxy stack. Single nginx serves the public song-analyzer
site from `./static/`; Caddy on the docker-proxy terminates TLS and
splits routing by path:

| Path | Auth | Backing |
|---|---|---|
| `/` | public | static analyzer app shell + per-track bundles (nginx) |
| `/audio/*` | Authelia forward-auth | full-quality audio files (nginx) |
| `/emotion/*` | Authelia forward-auth | prefix-stripped proxy to desktop `emotion-web` at `${MUSIC_UPSTREAM:-100.115.80.79:8094}` |

## Gating flip flag

`MUSIC_GATED_PATHS` (default `/audio/*`) is the Caddy path matcher for
the Authelia gate on the static side. Set it to `/*` in
`/home/opc/music/.env` to gate the entire site, then
`docker compose up -d`.

## Content pipeline

Per-track analysis bundles come from `~/Music/.viz/analyze.py`, which
writes `~/Music/.viz/out/tracks/<slug>/` plus `out/audio/<slug>.mp3`.
Push them with:

```sh
./deploy.sh            # everything under out/
./deploy.sh slug ...   # named bundles + manifest
```

The app shell (HTML/CSS/JS under `static/`, minus the gitignored
`static/tracks/` and `static/audio/`) deploys via `deploy-stacks.sh
music`.

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

`seafile-net` must already exist (it does, from the Seafile stack).

## Emotion upstream

- Desktop user service: `systemctl --user status emotion-web`
- Port: `8094` (opened only on `tailscale0`)
- Source: `nix/modules/services/emotion-web.nix` + `nix/pkgs/emotion-web.nix`
  + `.local/share/emotion-web/{server.py,static/index.html}`

If the desktop tailscale IP ever changes, set `MUSIC_UPSTREAM` in the
compose env to `<ip>:8094`. The default `100.115.80.79:8094` matches the
current desktop.

**WARNING:** `/emotion/*` is served through a prefix-stripping
`handle_path`, so emotion-web's UI must reference its API and assets
with RELATIVE URLs (`api/status`, `data/scores.csv`). Any absolute
`/api/...` or `/data/...` URL escapes the `/emotion/` mount and the
page silently breaks behind the proxy while still working on the
desktop.
