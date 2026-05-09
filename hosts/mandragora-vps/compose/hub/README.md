# `hub/` — landing page + apex redirect

Stack for `hub.mvrozanti.duckdns.org` (homepage dashboard) and the
apex `mvrozanti.duckdns.org` redirect to it.

## Containers

| Container | Image | Hosts |
|---|---|---|
| `homepage` | `ghcr.io/gethomepage/homepage:v1.5` | `hub.mvrozanti.duckdns.org` (reverse proxy) + `mvrozanti.duckdns.org` (302 redirect to hub) |

The redirect labels live on the homepage container itself — no
separate sidecar needed. Apex traffic hits the homepage container's
caddy_1 label, which short-circuits to a 302 before any reverse_proxy
runs, so the homepage backend is never touched for apex requests.

## Live location on VPS

`/home/opc/hub/` — bring up with:
```
cd /home/opc/hub && sudo docker compose up -d
```

Joins the existing `seafile-net` (declared `external: true`) so caddy
sees the labels. Caddy's docker-proxy picks up new label-bearing
containers on the watched network without any caddy restart.

## Config

`config/` is bind-mounted into the homepage container at `/app/config`.
Edit YAML, then `docker restart homepage`. Files:

- `settings.yaml` — site title, layout, theme
- `services.yaml` — link cards
- `bookmarks.yaml` — quick-access bookmarks
- `widgets.yaml` — top-bar widgets (resources, search, datetime)
- `docker.yaml`, `kubernetes.yaml` — empty placeholders (homepage
  expects them present even when unused)
- `custom.css`, `custom.js` — empty hooks for site-wide tweaks

## Env

`.env` in this directory (root-owned, gitignored) holds:
- `HUB_HOSTNAME` (default: `hub.mvrozanti.duckdns.org`)
- `SEAFILE_SERVER_HOSTNAME` (default: `mvrozanti.duckdns.org` — used
  for the apex-redirect label)
- `HOMEPAGE_IMAGE`, `HUB_CONFIG_VOLUME` — image/volume overrides
