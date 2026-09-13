# `authelia/` — single sign-on + TOTP gate

Stack for `auth.mvr.ac`. Sits in front of every hub vhost except
`mvr.ac` (GH Pages, public), `cal.mvr.ac` (CalDAV can't follow OAuth
redirects), and selective Seafile sync paths
(`/api2/*`, `/seafhttp/*`, `/seafdav/*`, `/notification/*`).

Three containers on `seafile-net`:

| Container | Image | Purpose |
|---|---|---|
| `authelia` | `authelia/authelia:4.39` | portal + forward-auth API at `:9091` |
| `authelia-redis` | `redis:7-alpine` | session storage at `:6379` |
| `authelia-skin` | `nginx:1.27-alpine` | mvr design-system skin at `:8080` |

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
- Elevated-session OTC (for security changes): 30 min lifespan.
- Default policy `deny`; explicit `two_factor` for
  `grafana.mvr.ac`, `term.mvr.ac`, `paste.mvr.ac`,
  `slither.mvr.ac`, `hub.mvr.ac`, `seafile.mvr.ac`,
  `mpd.mvr.ac`, `rgb.mvr.ac`, `gen.mvr.ac`, `chat.mvr.ac`,
  `claude.mvr.ac`. `auth.mvr.ac` itself is `bypass` (login portal).
- `cal.mvr.ac` is intentionally NOT in the access_control rules —
  Caddy doesn't route CalDAV through forward_auth at all, so the
  default-deny doesn't block it. CalDAV stays on Radicale's
  native htpasswd.
- WebAuthn / passkeys enabled but optional (every user has TOTP).

## Skin (`skin/`)

Authelia's frontend is compiled into the Go binary (`embed.FS`) and
`server.asset_path` only accepts `favicon.ico`, `logo.png` and
`locales/` — there is no supported CSS hook. So the mvr design system
is applied by a one-file nginx sidecar that proxies the **public
vhost only** and injects a stylesheet with `sub_filter`:

```
caddy ──► authelia-skin:8080 ──► authelia:9091     (auth.mvr.ac portal)
caddy ──────────────────────► authelia:9091        (forward_auth, untouched)
```

Every `forward_auth` label across the other stacks points straight at
`authelia:9091`, so the authorization path never passes through the
skin. If the skin dies, only the portal's appearance is affected;
swapping the `caddy:` labels back onto the `authelia` service restores
stock Authelia with no other change.

Injection happens on `index.html` only:

| `sub_filter` | Effect |
|---|---|
| `</head>` | adds `<link rel="stylesheet" href="/mvr/skin.css">` |
| `theme-color` | browser chrome follows `--mv-bg` instead of `#000` |
| `viewport` | adds `viewport-fit=cover` for safe-area insets |

Authelia's CSP is `style-src 'self' 'nonce-…'`, and nginx serves
`/mvr/skin.css` from the same origin, so no CSP change is needed.
`Host` is forwarded as `$http_host` (not `$host`, which drops the
port and breaks the templated `<base href>`); `X-Forwarded-*` pass
through untouched so Authelia still regulates on the real client IP.

`skin/static/skin.css` carries a copy of the `--mv-*` tokens from
`hub/static/theme.css` and overrides Authelia's MUI dark theme. It
hangs off stable hooks only — `#otp-input`, `[id="2fa-container"]`,
`[id$="-stage"]`, `#register-link`, `.Mui*` — never emotion's
generated class names.

> `2fa-container` starts with a digit, so `#2fa-container` is an
> **invalid CSS selector** and is silently dropped. Use
> `[id="2fa-container"]`.

What it fixes on mobile, beyond the palette: the six OTP inputs were
fixed-width `content-box` boxes that overflowed the viewport below
~360px (and wrapped to a second row on newer builds) — they are now
`flex: 1 1 0` with a 48px minimum tap target; `#2fa-container`'s
hard-coded `height: 200px` is released; and the stage's `90vh`
becomes `100dvh` so mobile browser chrome doesn't force a scroll.

Iterate on it with the lab harness described in
[`docs/authelia-skin.md`](../../../../docs/authelia-skin.md).

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
