# gpg.mvr.ac

Serves the owner's public PGP key as `text/plain` at
[gpg.mvr.ac](https://gpg.mvr.ac).

- **Public, no auth** — Caddy exposes it directly, no Authelia gate.
- Root (`/`) and `/pubkey.asc` both return `static/pubkey.asc` as
  `text/plain; charset=utf-8` so browsers render it inline instead of
  downloading. `/health` returns `ok` for the healthcheck.
- `static/pubkey.asc` is the armored export of key
  `921C6439C1B78654D303FA9F9C6ECAE6A7F357E6`
  (`<mvrozanti@hotmail.com>`), identical to
  <https://github.com/mvrozanti.gpg>.

## Import

```bash
curl -s https://gpg.mvr.ac | gpg --import
```

## Deploy

```bash
./deploy.sh
```

Rsyncs the compose file, `nginx.conf`, and `static/` to
`/home/opc/gpg/` on the VPS and runs `docker compose up -d`.
Compose-only — no nixos rebuild required.

## Refresh the key

Re-export and overwrite `static/pubkey.asc`, then `./deploy.sh`:

```bash
curl -s https://github.com/mvrozanti.gpg > static/pubkey.asc
```
