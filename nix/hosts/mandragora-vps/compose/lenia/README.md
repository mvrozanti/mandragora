# `lenia.mvr.ac` — GPU Lenia, public

Static-site slot mirroring the `rule110` stack. One nginx serves `./static/`
to `https://lenia.${MVR_AC:-mvr.ac}`. **No Authelia forward-auth** — public on
purpose. Caddy on the docker-proxy terminates TLS.

Multi-kernel, multi-channel Lenia running entirely in WebGL2 fragment shaders,
with an HDR bloom chain. Fifteen species: seven classic single-channel sets and
eight three-channel sets found by automated parameter search.

Upstream working copy lives at `~/Projects/lenia-experiments`. `static/` here is
the deployed snapshot and is the thing the audit and the VPS both read; re-sync
it with:

```sh
rsync -a --delete \
  --exclude='__pycache__' --exclude='.gitignore' \
  --exclude='serve.py' --exclude='mpdbridge.py' \
  --exclude='search.html' --exclude='derived-check.html' \
  --exclude='visual-check.html' --exclude='README.md' \
  ~/Projects/lenia-experiments/ static/
```

`serve.py` and `mpdbridge.py` are deliberately **not** deployed. They are the
local dev server and the MPD reactivity bridge, which read `/tmp/mpd.fifo` and
`localhost:6600` on the desktop. On the VPS there is no MPD; the app probes
`/mpd/status` on boot, finds nothing, and disables the whole Audio group with a
"no MPD bridge on this host" readout. Everything else works.

## First-time bring-up on the VPS

```sh
ssh opc@mandragora-vps
sudo mkdir -p /home/opc/lenia
sudo chown -R opc:opc /home/opc/lenia
exit

rsync -a /persistent/mandragora/nix/hosts/mandragora-vps/compose/lenia/ \
  opc@mandragora-vps:/home/opc/lenia/

ssh opc@mandragora-vps 'cd /home/opc/lenia && docker compose up -d'
```

`seafile-net` must already exist (it does, from the Seafile stack).

## Deploy / update content

```sh
./deploy.sh
```

nginx serves the new files immediately; no container restart.

## Requirements

WebGL2 with `EXT_color_buffer_float`. The page reports the problem instead of
failing silently; `webgl-check.html` prints a full capability report and
`boot-check.html` drives the engine directly and prints where it fails.
