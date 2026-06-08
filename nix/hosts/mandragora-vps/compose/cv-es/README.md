# cv-es.mvr.ac — Edgard's CV workshop

Public face of the Edgard CV editor that runs on the desktop
(`edgard-web.service`, tailnet `100.115.80.79:7691`).

This stack is a label-only alpine container — Caddy reads its labels and
reverse-proxies the public hostname to the desktop service through the
tailscale-VPS socat shim.

## Layout

```
docker-compose.yml   # caddy labels (basic_auth + reverse_proxy to desktop)
.env.example         # schema for the real .env (lives only on VPS)
```

On the VPS the slot is `/home/opc/cv-es/`:

```
/home/opc/cv-es/
├── docker-compose.yml   (rsynced from this dir)
└── .env                 (real CV_ES_BCRYPT — never committed)
```

## Bring-up

```sh
rsync -av --exclude='.env*' \
  /etc/nixos/mandragora/nix/hosts/mandragora-vps/compose/cv-es/ \
  opc@100.84.78.83:/home/opc/cv-es/

ssh opc@100.84.78.83 'cd /home/opc/cv-es && docker compose up -d'
```

The desktop tunnel must exist on the VPS host:

```sh
ssh opc@100.84.78.83 'sudo systemctl enable --now socat-tailnet@7691.service'
```

## Auth

A single basic_auth user `edgard` gated by a bcrypt hash. Rotate the hash by
regenerating it locally (`htpasswd -nbB -C 12 edgard <new-pw>`) and updating
`/home/opc/cv-es/.env` on the VPS, then `docker compose up -d`.

The desktop backend layers its own per-IP rate limits and path/slug allowlists
on top — `cv-es-proxy` is the door, the desktop is the safe.
