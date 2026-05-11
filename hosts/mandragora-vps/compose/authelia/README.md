# `authelia/` — single sign-on + TOTP gate

Stack for `auth.mvr.ac`. Sits in front of `grafana.`, `term.`, and
`paste.` via Caddy `forward_auth`. Two containers on `seafile-net`:

| Container | Image | Purpose |
|---|---|---|
| `authelia` | `authelia/authelia:4.39` | portal + forward-auth API at `:9091` |
| `authelia-redis` | `redis:7-alpine` | session storage at `:6379` |

## Live location

`/home/opc/authelia/`

```
cd /home/opc/authelia && sudo docker compose up -d
```

## Auth model

- Single user `m`, password + TOTP (registered with Aegis on phone).
- File-based user database at `config/users_database.yml`, argon2id-
  hashed password — gitignored even though the hash isn't a "secret"
  per se.
- Session cookies scoped to `*.mvr.ac` (set in
  `config/configuration.yml`).
- Brute-force regulation: 3 retries / 2 min window / 15 min ban.
- Default policy `deny`; only `auth.mvr.ac` (bypass — login portal
  itself) and `grafana.mvr.ac` / `term.mvr.ac` / `paste.mvr.ac`
  (two_factor) are routed through. Other services like
  `seafile.mvr.ac`, `cal.mvr.ac`, `hub.mvr.ac`, `slither.mvr.ac` are
  not behind forward_auth — Caddy doesn't call Authelia for them, so
  default-deny doesn't lock them out.

## Bootstrap

1. Generate three secrets and write to `/home/opc/authelia/.env`
   (root-owned, gitignored). 64-char random:
   ```bash
   docker run --rm authelia/authelia:4.39 \
     authelia crypto rand --length 64 --charset alphanumeric
   ```
   Run three times; populate:
   ```
   AUTHELIA_JWT_SECRET=...
   AUTHELIA_SESSION_SECRET=...
   AUTHELIA_STORAGE_ENCRYPTION_KEY=...
   MVR_AC=mvr.ac
   TZ=America/Sao_Paulo
   ```

2. Generate argon2id hash for `m`'s password:
   ```bash
   docker run --rm authelia/authelia:4.39 \
     authelia crypto hash generate argon2 --password '<password>'
   ```
   Write `config/users_database.yml`:
   ```yaml
   users:
     m:
       disabled: false
       displayname: 'm'
       password: '<argon2id hash from above>'
       email: 'mvrozanti@gmail.com'
       groups:
         - admins
   ```

3. `sudo docker compose up -d`.

4. `curl -sI https://auth.mvr.ac/` → 200, body says "Login -
   Authelia".

5. From a browser on tailnet (so Caddy lets you through): open
   `https://auth.mvr.ac/`, sign in with `m` + the bootstrap
   password, scan TOTP QR with Aegis on phone, save the recovery
   seed for offline backup.

## Add a new user

Edit `config/users_database.yml` on the VPS (root-owned), add a new
entry under `users:`. Authelia watches the file (`watch: true` in
config) and reloads within 5 min — or restart the container for an
immediate pickup:
```
sudo docker restart authelia
```

## Recovery from lost phone

Authelia has no first-class "backup codes" — it stores TOTP secrets
in `data/db.sqlite3`. Recovery paths:

1. Pre-registered second device (recommended at enrollment): just
   use it.
2. Direct VPS access (Tailscale SSH always available): edit
   `users_database.yml` to remove the user's TOTP, log back in,
   re-enroll.
3. Restore `data/db.sqlite3` from backup.

## Disk

Authelia ~80 MB image + sqlite db tens of KB. Redis alpine ~40 MB
image + appendonly file tens of KB. Total footprint negligible.
