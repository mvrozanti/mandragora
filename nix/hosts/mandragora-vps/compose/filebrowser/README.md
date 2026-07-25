# `filebrowser/` — on-demand public sharing of desktop files (`files.mvr.ac`)

Reverse-proxy-only stack. The actual filebrowser runs on **mandragora-desktop**
(`nix/modules/services/filebrowser.nix`), rooted at `/`, so you can publish any
file or directory on the machine on demand — no fixed served folder, no copy to
the VPS. Files stream from the desktop disk over tailscale (range requests →
video seeks).

This is the "big / arbitrary local content" tier, complementing:
- `gokapi` (`share.mvr.ac`) — quick ephemeral single-file *drop* (stored on VPS)
- `filebrowser` (`files.mvr.ac`) — publish existing local files/dirs of any size

## How you publish

- **Web UI** (`files.mvr.ac`, authelia-gated): browse → Share → set expiry +
  optional password → copy the `/share/<hash>` link.
- **Terminal** (`share` command on the desktop):
  ```
  share ~/movies/thing.mkv        # no expiry
  share ~/movies/thing.mkv 2d     # expires in 2 days
  share ~/movies 3h hunter2       # dir, 3h expiry, password
  ```
  Prints `https://files.mvr.ac/share/<hash>`.

## Auth model (caddy is the gate)

filebrowser runs `auth.method=noauth` with a read-only user (download + share
only; no create/delete/modify), so the app has no gate of its own. Caddy splits
by path:

| paths | policy |
|---|---|
| `/share/*`, `/api/public/*`, `/static/*` | **public** (the share links) |
| everything else (browse, `/api/resources`, `/api/raw`, settings) | authelia `two_factor` |

Root is `/` on the desktop, so the authelia gate is the only thing between the
internet and the whole disk — the `@public` matcher is the security boundary. A
share link only ever exposes the one shared path (download/metadata by hash).

## Upstream

`${FILEBROWSER_UPSTREAM:-100.115.80.79:8096}` — desktop tailnet IP, port opened
on `tailscale0` only (see `mandragora.hub.services.filebrowser`). No socat shim
needed; caddy reaches the tailnet IP directly like the `semantic` stack.

## Live location

`/home/opc/filebrowser/`

```
cd /home/opc/filebrowser && sudo docker compose up -d
```

## Verification

- `curl -sI https://files.mvr.ac/` → `302 → auth.mvr.ac` (browse gated).
- `curl -s https://files.mvr.ac/api/public/dl/<hash>/<name>` → file bytes, no auth.
- `share ~/some/file` on the desktop → prints a link that downloads without auth.
