# `manifold.mvr.ac` — public maps from `manifold-2`

Static-site slot mirroring the `rule110` stack. Single nginx serves
whatever sits in `./static/` to `https://manifold.${MVR_AC:-mvr.ac}`.
**No Authelia forward-auth** — public on purpose. Caddy on the
docker-proxy terminates TLS.

## First-time bring-up on the VPS

```sh
ssh opc@mandragora-vps
sudo mkdir -p /home/opc/manifold
sudo chown -R opc:opc /home/opc/manifold
exit

rsync -a /persistent/mandragora/nix/hosts/mandragora-vps/compose/manifold/ \
  opc@mandragora-vps:/home/opc/manifold/

ssh opc@mandragora-vps 'cd /home/opc/manifold && docker compose up -d'
```

`seafile-net` must already exist (it does, from the Seafile stack).

## Deploy / update content

The maps are build artifacts of `~/Projects/manifold-2` — each one a
single self-contained HTML file with no runtime network access. To
rebuild them and publish the current state:

```sh
~/Projects/manifold-2/scripts/deploy-site.sh
```

The script builds the map set, writes the landing index, and rsyncs
everything into `/home/opc/manifold/static/` on the VPS. nginx serves
the new files immediately — no container restart.

## Why this slot exists separately from `demo`

`demo.mvr.ac` is the catch-all "current demo" subdomain that hosts
`fake-obsidian`. `manifold.mvr.ac` is a stable, named slot for the
manifold-2 maps, so a link keeps working when `demo` rotates.
