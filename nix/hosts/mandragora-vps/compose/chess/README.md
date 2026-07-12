# chess

Static frontend for [Chess Lens](https://github.com/mvrozanti/chess-lens-ultimate)
served at `https://chess.mvr.ac`. The heavy backend (Kotlin/Spring + ClickHouse +
Redis + Postgres + Stockfish) runs on the **desktop** (Mandragora) and is reached
over tailscale.

## Routing

- `https://chess.mvr.ac/api/*` → reverse-proxied to the desktop backend
  (`CHESS_BACKEND`, default `100.115.80.79:8080`) over the tailnet, prefix kept.
- everything else → nginx serving the built SPA (`static/`), with SPA fallback to
  `index.html`.

## Deploy

```sh
# build the SPA on the desktop
cd ~/Projects/chess-lens-ultimate/frontend && npm run build

# push static + compose to the VPS slot
rsync -a --delete dist/ opc@mandragora-vps:/home/opc/chess/static/
rsync -a docker-compose.yml nginx.conf .env opc@mandragora-vps:/home/opc/chess/

# bring it up
ssh opc@mandragora-vps 'cd /home/opc/chess && docker compose up -d'
```

The backend instance is homologation — auth is Clerk (dev instance), keys wired on
the desktop via sops (`/run/secrets/clerk/secret`) and the frontend publishable
key baked into the build.
