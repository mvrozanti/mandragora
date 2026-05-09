# `radicale/` — CalDAV / CardDAV server

Stack for `cal.mvr.ac`. Lightweight Python CalDAV+CardDAV server
(Radicale 3) suitable for syncing calendars and contacts with
DAVx⁵ on Android, Thunderbird, Apple Calendar, etc.

## Container

| Container | Image | Port | Persistence |
|---|---|---|---|
| `radicale` | `tomsquest/docker-radicale:3.5.4.0` | `5232` | bind mounts `./data` (collections) + `./config:ro` (server config + users) |

The image is hardened upstream: runs as uid 2999, read-only root
filesystem, dropped capabilities, pids/memory limits — Radicale
itself just needs ~30 MB.

## Live location

`/home/opc/radicale/`

```
cd /home/opc/radicale && sudo docker compose up -d
```

Joins `seafile-net` (declared `external: true`) so caddy sees the
labels.

## Auth

`config/users` is an htpasswd file with bcrypt-encrypted entries.
Read-only mounted into the container at `/config/users`. Each line:
`<user>:<bcrypt-hash>`.

Add a new user from the host:
```
sudo docker run --rm tomsquest/docker-radicale:3.5.4.0 \
  htpasswd -nbB <user> <password> | sudo tee -a /home/opc/radicale/config/users
```

`[rights] type = owner_only` in `config` means each user only sees
their own collections (under `/<user>/`).

## Public access

`cal.mvr.ac` is public — no tailnet IP gate. CalDAV needs to be
reachable from Android phones not on the tailnet. Defense-in-depth
via:
- Caddy TLS termination (Let's Encrypt prod cert)
- Radicale htpasswd with bcrypt
- `owner_only` rights model

If you'd rather lock it down to tailnet, add the same
`@notTailnet remote_ip 100.64.0.0/10 → 403` matcher used on
`term`/`paste`/`grafana` and install Tailscale on Android.

## Android setup (DAVx⁵)

1. Install [DAVx⁵](https://f-droid.org/en/packages/at.bitfire.davdroid/).
2. **Add account → "Login with URL and username"**
3. Base URL: `https://cal.mvr.ac/`
4. Username: as in `config/users`
5. Password: as set when generating the htpasswd entry
6. After detection, enable the calendar(s) you want to sync.

DAVx⁵ supports both CalDAV (calendars) and CardDAV (contacts) on
the same Radicale endpoint. Calendars created in DAVx⁵ appear in
the standard Android Calendar app and Etar; contacts appear in the
system contacts.

## Verification

```
curl -sI -u m:$PASS https://cal.mvr.ac/
# → 200 OK + DAV headers

curl -s -u m:$PASS -X PROPFIND https://cal.mvr.ac/m/ \
  -H 'Depth: 0' -H 'Content-Type: application/xml' \
  --data '<?xml version="1.0"?><propfind xmlns="DAV:"><prop><resourcetype/></prop></propfind>'
# → 207 Multi-Status with collection listing
```
