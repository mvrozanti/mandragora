# `demo.mvr.ac` — public static-site slot

Single-container nginx that serves whatever sits in `./static/` to
`https://demo.${MVR_AC:-mvr.ac}`. **No Authelia forward-auth** — this
is the project's public-demo subdomain. Caddy still terminates TLS via
the docker-proxy.

## First-time bring-up on the VPS

```sh
ssh opc@mandragora-vps
sudo mkdir -p /home/opc/demo
sudo chown -R opc:opc /home/opc/demo
exit

rsync -a /persistent/mandragora/nix/hosts/mandragora-vps/compose/demo/ \
  opc@mandragora-vps:/home/opc/demo/

ssh opc@mandragora-vps 'cd /home/opc/demo && docker compose up -d'
```

`seafile-net` must already exist (it does, from the Seafile stack).

## Current tenant: `fake-obsidian`

Build + deploy from the desktop with the colocated script:

```sh
~/Projects/fake-obsidian/deploy.sh
```

That script:
- regenerates `graph.json` from the vault,
- rsyncs `index.html`, `graph.json`, and the markdown vault into
  `/home/opc/demo/static/` on the VPS,
- nginx serves the new files immediately — no container restart
  needed.

## Adding a different tenant later

Replace the contents of `./static/` (or repoint the bind-volume via
`DEMO_STATIC_VOLUME`). Container config stays the same.
