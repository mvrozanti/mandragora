# gpg.mvr.ac

Public PGP key **and** a client-side-encrypted mail drop.

## Surfaces

| Path | Auth | Purpose |
|---|---|---|
| `GET /` (`Accept: */*`) | none | armored public key as `text/plain` — `curl … \| gpg --import` |
| `GET /` (`Accept: text/html`) | none | the interactive page (copy key, leave mail, verify signatures) |
| `GET /pubkey.asc` | none | always the raw key as `text/plain` |
| `POST /inbox` | none — public, rate-limited | accept one ASCII-armored `PGP MESSAGE` |
| `GET /api/messages` | Authelia | list stored ciphertext (metadata + unread count) |
| `GET /api/messages/{id}` | Authelia | fetch one ciphertext blob to decrypt locally |
| `POST /api/messages/{id}/read`, `DELETE /api/messages/{id}` | Authelia | mark read / delete |

Content negotiation is by `Accept`: browsers send `text/html` and get the
page; `curl`/`wget` send `*/*` and get the key, so the documented
`curl -s https://gpg.mvr.ac | gpg --import` still works unchanged.

## The page (browser)

1. **Public key** — rendered inline with copy-to-clipboard and download-`.asc`.
2. **Leave an encrypted message** — encrypted **in the browser** against the
   served key (OpenPGP.js, vendored at `app/static/openpgp.min.js`) *before*
   the POST. The server only ever stores ciphertext; it cannot read plaintext.
3. **Verify a message signed by me** — paste a clear-signed / armored signed
   message; verified against the served key, all client-side.
4. **Inbox** (only rendered when the `/api/*` calls pass Authelia) — lists
   stored ciphertext with an unread badge. Decryption happens **locally**:
   paste your private key once per session (held in memory, never sent) and
   the browser decrypts each blob on demand.

## Safety (public inbox faces the internet)

- Per-IP rate limit: `GPG_RATE_PER_MIN` (default 3/min) and
  `GPG_RATE_PER_DAY` (default 50/day), keyed on `X-Forwarded-For`.
- Per-message cap `GPG_MAX_MSG_BYTES` (default 64 KiB); bodies must match the
  armored `PGP MESSAGE` envelope or are rejected `400`.
- Storage is bounded and self-pruning (oldest-first) by `GPG_MAX_MESSAGES`
  (default 5000) and `GPG_MAX_TOTAL_BYTES` (default 256 MiB) — well under half
  the VPS free space. Raise only after checking `df` on the box.
- Reader endpoints (`/api/*`) are gated by Authelia at Caddy **and**
  re-checked in-app via the `Remote-User` header.

## Storage

SQLite at `./data/inbox.db` (volume-mounted at `/data`). Ciphertext only.

## Deploy

```bash
./deploy.sh
```

Rsyncs `docker-compose.yml` + `app/` to `/home/opc/gpg/` and runs
`docker compose up -d --build`. Compose-only — no nixos rebuild.

## Refresh the key

Re-export and overwrite `app/static/pubkey.asc`, then `./deploy.sh`:

```bash
curl -s https://github.com/mvrozanti.gpg > app/static/pubkey.asc
```

Key `921C6439C1B78654D303FA9F9C6ECAE6A7F357E6`, identical to
<https://github.com/mvrozanti.gpg>.
