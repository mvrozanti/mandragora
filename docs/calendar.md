# Calendar

One calendar everywhere: the calendars the operator's email accounts own,
shown on the phone by its stock app, on the desktop by khal, on the kindle
by a read-only tile. Why the accounts and not the self-hosted server: vault
note *Calendar truth lives in the email accounts*.

```
account ──▶ phone      stock calendar app, signed in to the account
        ──▶ desktop    calendar-sync.timer (5 min) ─▶ vdirsyncer ─▶ ~/.local/share/calendars/<account>/
                         davmail.service :1080        the Hotmail calendar as CalDAV, localhost only
                         khal (Alt+K)                 reads and writes those folders
                         mandragora-agenda :6616      khal list, for the kindle
        ──▶ kindle     Agenda tile ─▶ mandragora-agenda on the LAN
```

## Pieces

| Piece | Where |
|---|---|
| pairs and storages | `.config/vdirsyncer/config` |
| what khal shows | `.config/khal/config` (one `discover` entry per account) |
| the timer's job | `.local/bin/calendar-sync.sh`: syncs every signed-in account, stamps `last-sync` |
| sign-in | `.local/bin/calendar-login.sh`, and for Hotmail `.local/bin/calendar-oauth.py` |
| the Hotmail bridge | `.config/davmail/davmail.properties`, copied into the state dir at start because DavMail writes to it |
| units and packages | `nix/modules/user/calendar.nix` |
| kindle side | `nix/hosts/mandragora-kindle/README.md`, section Agenda |

## State outside the repo

All of it under `~/.local/state/`, mode 700, none of it in sops:

| File | What |
|---|---|
| `davmail/tokens.properties` | the Hotmail sign-in, a Java properties line keyed by the account; DavMail rewrites it encrypted with the CalDAV password in `.config/vdirsyncer/config`. Non-empty is what starts `davmail.service` and makes `calendar-sync` include the account |
| `vdirsyncer/google-client-id`, `vdirsyncer/google-client-secret` | the operator's own sign-in key from Google's console |
| `vdirsyncer/google.token` | the Google sign-in; its presence is what makes `calendar-sync` include the account |
| `vdirsyncer/status/` | vdirsyncer's memory of what it synced |
| `vdirsyncer/last-sync` | epoch of the last run in which every signed-in account synced |

Losing the directory loses no event: the accounts hold the data. Sign in
again and the folders refill.

## Signing in

`calendar-login google`. The first time there is no key and it prints the five
console steps; they end with a downloaded `client_secret_*.json` in
`~/Downloads`, which the next run splits into the two key files and deletes.
The project must be published, not left in testing: a testing project's
sign-in is ended by Google every seven days. Then a browser tab opens for the
account's consent, the calendars are discovered and the first sync runs.

`calendar-login hotmail`. Microsoft has no CalDAV, so DavMail 7 translates it
from Microsoft Graph on `127.0.0.1:1080`. The sign-in is an authorization-code
flow on a local listener: the command prints `http://localhost:<port>/`, which
forwards to Microsoft's page, and the answer comes back to the listener, so a
refusal is printed with Microsoft's own reason. Three things that were tried
and do not work for a personal account, so nobody tries them again:

- DavMail's device-code sign-in: Microsoft's page rejects the code the moment
  it is typed and calls it expired while it is still valid.
- DavMail's built-in app registration with a local redirect: it only accepts
  the paste-the-address-back flow. The helper uses the registration the
  desktop mail already uses, which accepts `http://localhost`.
- A sign-in without the mail permission: DavMail's Graph backend refuses to
  start a session without `Mail.ReadWrite`, calendar-only or not.

The first Hotmail sync pulls every event one by one and takes minutes; later
runs take seconds.

## Behaviour worth knowing

- Conflicts: the server's copy wins (`conflict_resolution = "b wins"`).
- khal names the two Hotmail calendars itself: `hotmail` (the default for
  new events) and `feriados`, the account's holiday calendar, read-only.
  Google's are discovered and carry the account's display names.
- On a host that shares the khal config but does not sync, khal creates
  those two folders empty instead of failing.
- A calendar the account marks read-only (holidays, birthdays) refuses edits
  on the server; the sync run then fails for that account until the local
  edit is undone.
- `systemctl --user status calendar-sync` shows the last run; the kindle
  tile's header shows the age of the last good one.
