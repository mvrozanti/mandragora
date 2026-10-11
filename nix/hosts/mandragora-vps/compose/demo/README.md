# `demo.mvr.ac` — public static site (vault graph + gource)

Nginx container that serves whatever sits in `./static/` to
`https://demo.${MVR_AC:-mvr.ac}`. **No Authelia** — this is the
project's public-demo subdomain. Caddy terminates TLS via the
docker-proxy.

Two views live here:

- **`/`** — the [vault-graph](https://github.com/mvrozanti/vault-graph)
  viewer over the mandragora knowledge vault.
- **`/gource.html`** — on-demand gource render of the mandragora
  repo git history (form → MP4). The form POSTs to
  `/api/gource/render`, which caddy path-routes to the `gource-api`
  container in the [gource](../gource/) stack. See that stack's
  README for the render pipeline (desktop-first, VPS fallback).

Both pages are on the `--mv-*` design system: `theme.css`,
`theme.js` and `components.css` are byte-identical copies of
`compose/hub/static/`, and `demo.css` holds the page layout, using
tokens only. The shared top bar is the `.mv-tabs` primitive. The graph
canvas takes its colours from the `--vg-*` properties that `demo.css`
maps onto the tokens, and re-tints on the `mv-theme` event.

## Static layout (`./static/`)

| path                                                    | owned by                  |
|---------------------------------------------------------|---------------------------|
| `index.html`, `gource.html`                             | this repo (deploy.sh)     |
| `demo.css`, `gource.js`                                 | this repo (deploy.sh)     |
| `theme.css`, `theme.js`, `components.css`               | copies of `hub/static/`   |
| `favicon.svg`, `robots.txt`, `sitemap.xml`, `.well-known/` | this repo               |
| `vendor/vault-graph/`                                   | this repo (vendored)      |
| `vault/`, `graph.json`                                  | `publish-vault.sh`        |

Two scripts write `/home/opc/demo/static/`, on disjoint paths.
`deploy.sh` owns every page file; `publish-vault.sh` owns only `vault/`
and `graph.json`, and is what `mandragora-vault publish` runs after an
agent switch. Until 2026-10-11 the publish step ran
`~/Projects/demo/deploy.sh`, which also pushed its own untabbed
`index.html`, so every vault publish silently unlinked `/gource.html`.
Audit check `18-demo-deployed` diffs the served page files against
`static/` to keep a second writer from coming back.

## First-time bring-up on the VPS

```sh
ssh opc@mandragora-vps
sudo mkdir -p /home/opc/demo/static
sudo chown -R opc:opc /home/opc/demo
exit

rsync -a /etc/nixos/mandragora/nix/hosts/mandragora-vps/compose/demo/docker-compose.yml \
  opc@mandragora-vps:/home/opc/demo/
./deploy.sh

ssh opc@mandragora-vps 'cd /home/opc/demo && docker compose up -d'
```

`seafile-net` must already exist (it does, from the Seafile stack).
The `gource` stack must also be running for `/api/gource/*` requests
to resolve — bring it up next via `compose/gource/README.md`.

## Deploying static changes

```sh
./deploy.sh
```

Rsyncs everything under `static/` into `/home/opc/demo/static/`
**except** `vault/`, `vault-graph/`, and `graph.json`. nginx serves
the new files immediately — no container restart.

Override the remote via `REMOTE=opc@host` / `REMOTE_DIR=…` env vars
if you need a different target.

## Caddy

Path-routed inside the single `https://demo.mvr.ac` vhost:

| match                | upstream                                                     |
|----------------------|--------------------------------------------------------------|
| `/api/theme`         | desktop palette, rewritten to `?colors=1` (design system)    |
| `/api/gource/*`      | `gource-api:8080` (compose `gource`)                         |
| everything else      | `demo:80` (nginx, this stack)                                |

`gource-api` must be on `seafile-net` and have its `container_name`
set so caddy can resolve it by name.
