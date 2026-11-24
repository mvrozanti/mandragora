# `meme.mvr.ac` — meme search and tagging runner

Search over the meme library (caption text, tags, labels, filenames) plus a
runner for the `meme` tagger. The library is the folder list in
`mandragora.memeWeb.roots` (today `~/Documents/PhoneDownloads` and the 4chan
folder); search, the Start button, the reindex button and the nightly
`meme-nightly-tag` run all read it as `VTAG_SEARCH_ROOTS`.

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

## Deploying

`docker-compose.yml` is generated from [`../proxy-stacks.json`](../proxy-stacks.json)
by [`../generate-proxy-stacks.py`](../generate-proxy-stacks.py) — edit the
manifest and re-run the generator, never this file. Audit check
`11-proxy-stacks` gates the drift.

Deploy by landing the change: `mandragora-switch` runs
`deploy-stacks.sh --sync`, which deploys every enrolled stack master changed.
Never `rsync` into `/home/opc/` by hand. Changes to the server itself live in
the `meme-web` module and the pinned vtag rev in `nix/pkgs/meme-cli.nix`, and
ship with the same switch.

## Override upstream

If the desktop's tailscale IP ever changes, set `MEME_UPSTREAM` in the
compose env (or alongside `MVR_AC` in the docker-proxy environment) to
`<ip>:8093`. The default `100.115.80.79:8093` matches the current
desktop.
