# `rule110.mvr.ac` — public viz for `rule-110-compiler`

Static-site slot mirroring the `demo` stack. Single nginx serves whatever
sits in `./static/` to `https://rule110.${MVR_AC:-mvr.ac}`. **No
Authelia forward-auth** — public on purpose. Caddy on the docker-proxy
terminates TLS.

## First-time bring-up on the VPS

```sh
ssh opc@mandragora-vps
sudo mkdir -p /home/opc/rule110
sudo chown -R opc:opc /home/opc/rule110
exit

rsync -a /persistent/mandragora/nix/hosts/mandragora-vps/compose/rule110/ \
  opc@mandragora-vps:/home/opc/rule110/

ssh opc@mandragora-vps 'cd /home/opc/rule110 && docker compose up -d'
```

`seafile-net` must already exist (it does, from the Seafile stack).

## Deploy / update content

The viz is a flat directory of static files at
`~/Projects/rule-110-compiler/viz/`. To publish the current state:

```sh
~/Projects/rule-110-compiler/scripts/deploy_viz.sh
```

The script rsyncs `viz/*` into `/home/opc/rule110/static/` on the VPS.
nginx serves the new files immediately — no container restart.

## Why this slot exists separately from `demo`

`demo.mvr.ac` is the catch-all "current demo" subdomain that currently
hosts `fake-obsidian`. `rule110.mvr.ac` is a stable, named slot for the
rule-110 layered-visualization page so a link in a paper / README /
discussion thread keeps working when `demo` rotates to whatever comes
next.
